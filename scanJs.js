#!/usr/bin/env node

// Node.js built-ins and Babel packages
const fs = require('fs');
const path = require('path');
const https = require('https');
const parser = require('@babel/parser');
const traverse = require('@babel/traverse').default;

// Validate command-line arguments
if (process.argv.length < 3) {
  console.error('Usage: node check_packages.js <target-directory>');
  process.exit(1);
}
const rootDir = process.argv[2];

// Recursively collect all .js and .ts files under a directory
function findFiles(dir) {
  let results = [];
  try {
    for (const entry of fs.readdirSync(dir)) {
      const fullPath = path.join(dir, entry);
      // Skip node_modules or hidden directories
      if (entry === 'node_modules' || entry.startsWith('.')) continue;
      const stat = fs.lstatSync(fullPath);
      if (stat.isDirectory()) {
        // Recurse into subdirectory
        results = results.concat(findFiles(fullPath));
      } else if (stat.isFile() && /\.(js|ts)x?$/.test(fullPath)) {
        // Include .js, .jsx, .ts, .tsx files
        results.push(fullPath);
      }
    }
  } catch (err) {
    // Gracefully handle permissions or other fs errors
    console.warn(`Warning: Unable to read directory ${dir}: ${err.message}`);
  }
  return results;
}

// Parse a file with Babel and extract imported package names
function extractImports(filePath) {
  const pkgNames = [];
  let code;
  try {
    code = fs.readFileSync(filePath, 'utf8');
  } catch (err) {
    console.warn(`Warning: Cannot read file ${filePath}: ${err.message}`);
    return pkgNames;
  }
  let ast;
  try {
    // Improved parser configuration with better error handling
    ast = parser.parse(code, {
      sourceType: 'unambiguous',
      plugins: [
        'exportDefaultFrom',
        'decorators-legacy',
        'decoratorAutoAccessors',
        'classProperties',
        'classPrivateProperties',
        'classPrivateMethods',
        'optionalChaining',
        'nullishCoalescingOperator',
        'topLevelAwait',
        'dynamicImport',
        'jsx',
        'typescript'
      ],
      errorRecovery: true, // Continue parsing even with errors
      attachComment: false, // Reduce memory usage
    });
  } catch (err) {
    console.warn(`Warning: Failed to parse ${filePath}: ${err.message}`);
    return pkgNames;
  }

  // Traverse the AST to find import/require statements
  traverse(ast, {
    // Handle ES6 import statements: import ... from 'pkg';
    ImportDeclaration(path) {
      const source = path.node.source && path.node.source.value;
      if (source && typeof source === 'string') {
        pkgNames.push(source);
      }
    },
    // Handle CommonJS require(): require('pkg');
    CallExpression(path) {
      const callee = path.node.callee;
      // require('pkg')
      if (
        callee.type === 'Identifier' &&
        callee.name === 'require' &&
        path.node.arguments.length === 1
      ) {
        const arg = path.node.arguments[0];
        if (arg.type === 'StringLiteral') {
          pkgNames.push(arg.value);
        }
      }
      // dynamic import('pkg')
      else if (callee.type === 'Import' && path.node.arguments.length === 1) {
        const arg = path.node.arguments[0];
        if (arg.type === 'StringLiteral') {
          pkgNames.push(arg.value);
        }
      }
    }
  });

  return pkgNames;
}

// Improved package name validation
function isValidPackageName(name) {
  // Skip relative/absolute paths, scoped packages, and Node.js built-ins
  if (name.startsWith('.') || 
      name.startsWith('/') || 
      name.startsWith('@') ||
      name.startsWith('node:') ||
      name.includes('\\')) { // Windows paths
    return false;
  }
  
  // Skip common non-package imports
  const skipPatterns = [
    /^https?:\/\//, // URLs
    /^\.\.?\//,     // Relative paths
    /^[a-z]:/i,     // Windows drive letters
  ];
  
  return !skipPatterns.some(pattern => pattern.test(name));
}

// Extract package name from import specifier
function extractPackageName(name) {
  // Handle subpath imports like 'lodash/map' or '@types/node'
  const parts = name.split('/');
  
  // If it starts with @, it's a scoped package - take first two parts
  if (name.startsWith('@') && parts.length >= 2) {
    return parts.slice(0, 2).join('/');
  }
  
  // Otherwise, take just the first part
  return parts[0];
}

// Improved HTTP check with timeout and better error handling
function checkPackageAvailability(name) {
  return new Promise((resolve) => {
    const url = `https://registry.npmjs.org/${encodeURIComponent(name)}`;
    
    const req = https.get(url, (res) => {
      const status = (res.statusCode === 404) ? 'Available' : 'Taken';
      resolve({ name, status, error: null });
    });
    
    req.setTimeout(10000, () => {
      req.destroy();
      resolve({ name, status: 'Timeout', error: 'Request timeout' });
    });
    
    req.on('error', (err) => {
      resolve({ name, status: 'Error', error: err.message });
    });
  });
}

// Main execution function
async function main() {
  // Step 1: Collect all files
  console.log('Scanning files...');
  const allFiles = findFiles(rootDir);
  console.log(`Found ${allFiles.length} files to analyze`);

  // Step 2: Extract all package names from imports/requires
  let allPackages = [];
  for (const file of allFiles) {
    const packages = extractImports(file);
    allPackages = allPackages.concat(packages);
  }
  console.log(`Found ${allPackages.length} import statements`);

  // Step 3: Filter and normalize package names
  let candidates = allPackages
    .filter(isValidPackageName)
    .map(extractPackageName)
    .filter(name => name && name.length > 0);

  // Step 4: Deduplicate package names
  candidates = Array.from(new Set(candidates));
  console.log(`Found ${candidates.length} unique package candidates`);

  if (candidates.length === 0) {
    console.log('No package names found to check.');
    return;
  }

  // Step 5: Check npm registry availability with concurrency control
  console.log('Checking package availability...');
  const results = [];
  const BATCH_SIZE = 5; // Process 5 packages at a time to avoid rate limiting
  
  for (let i = 0; i < candidates.length; i += BATCH_SIZE) {
    const batch = candidates.slice(i, i + BATCH_SIZE);
    const batchPromises = batch.map(name => checkPackageAvailability(name));
    
    const batchResults = await Promise.all(batchPromises);
    results.push(...batchResults);
    
    // Progress indicator
    const processed = Math.min(i + BATCH_SIZE, candidates.length);
    console.log(`Processed ${processed}/${candidates.length} packages...`);
    
    // Small delay between batches to be respectful to the registry
    if (i + BATCH_SIZE < candidates.length) {
      await new Promise(resolve => setTimeout(resolve, 100));
    }
  }

  // Step 6: Output results
  // Sort results by name for consistency
  results.sort((a, b) => a.name.localeCompare(b.name));

  // Prepare output
  const nameColWidth = Math.max(...results.map(r => r.name.length), 12) + 2;
  let output = '';
  output += `${'Package Name'.padEnd(nameColWidth)}Status\n`;
  output += `${'-'.repeat(nameColWidth)}-------\n`;
  
  const availablePackages = [];
  
  for (const result of results) {
    output += `${result.name.padEnd(nameColWidth)}${result.status}`;
    if (result.error) {
      output += ` (${result.error})`;
    }
    output += '\n';
    
    if (result.status === 'Available') {
      availablePackages.push(result.name);
    }
  }

  // Print to console
  console.log('\n' + output.trim());
  
  // Show summary
  const availableCount = results.filter(r => r.status === 'Available').length;
  const errorCount = results.filter(r => r.status === 'Error' || r.status === 'Timeout').length;
  
  console.log(`\nSummary:`);
  console.log(`- Total packages checked: ${results.length}`);
  console.log(`- Available: ${availableCount}`);
  console.log(`- Taken: ${results.length - availableCount - errorCount}`);
  console.log(`- Errors: ${errorCount}`);
  
  if (availablePackages.length > 0) {
    console.log(`\nAvailable package names: ${availablePackages.join(', ')}`);
  }

  // Save to output.txt
  fs.writeFileSync('output.txt', output, 'utf8');
  console.log('\nResults saved to output.txt');
}

// Run the main function
main().catch(err => {
  console.error('Unexpected error:', err);
  process.exit(1);
});
