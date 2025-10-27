#!/usr/bin/env node

// Node.js built-ins and external packages
const fs = require('fs').promises;
const path = require('path');
const parser = require('@babel/parser');
const traverse = require('@babel/traverse').default;
const https = require('https');

// Node.js built-in modules (as of Node.js 18+)
const NODE_BUILTIN_MODULES = new Set([
  'assert', 'async_hooks', 'buffer', 'child_process', 'cluster', 'console',
  'constants', 'crypto', 'dgram', 'diagnostics_channel', 'dns', 'domain',
  'events', 'fs', 'http', 'http2', 'https', 'inspector', 'module', 'net',
  'os', 'path', 'perf_hooks', 'process', 'punycode', 'querystring', 'readline',
  'repl', 'stream', 'string_decoder', 'timers', 'tls', 'trace_events', 'tty',
  'url', 'util', 'v8', 'vm', 'wasi', 'worker_threads', 'zlib',
  // Common aliases
  'node:assert', 'node:async_hooks', 'node:buffer', 'node:child_process', 
  'node:cluster', 'node:console', 'node:constants', 'node:crypto', 'node:dgram',
  'node:diagnostics_channel', 'node:dns', 'node:domain', 'node:events', 'node:fs',
  'node:http', 'node:http2', 'node:https', 'node:inspector', 'node:module',
  'node:net', 'node:os', 'node:path', 'node:perf_hooks', 'node:process',
  'node:punycode', 'node:querystring', 'node:readline', 'node:repl',
  'node:stream', 'node:string_decoder', 'node:timers', 'node:tls',
  'node:trace_events', 'node:tty', 'node:url', 'node:util', 'node:v8',
  'node:vm', 'node:wasi', 'node:worker_threads', 'node:zlib'
]);

// Validate command-line arguments
if (process.argv.length < 3) {
  console.error('Usage: node scan.js <target-directory> [output-file]');
  process.exit(1);
}

const rootDir = process.argv[2];
const outputFile = process.argv[3] || 'available-packages.txt';

// Store package occurrences with file paths
const packageOccurrences = new Map();

/**
 * Recursively collect all JavaScript and TypeScript files under a directory
 */
async function findFiles(dir) {
  let results = [];
  try {
    const entries = await fs.readdir(dir);
    
    for (const entry of entries) {
      const fullPath = path.join(dir, entry);
      
      // Skip node_modules, dist, build, and hidden directories
      if (entry === 'node_modules' || entry === 'dist' || entry === 'build' || entry.startsWith('.')) {
        continue;
      }
      
      try {
        const stat = await fs.stat(fullPath);
        
        if (stat.isDirectory()) {
          const subFiles = await findFiles(fullPath);
          results = results.concat(subFiles);
        } else if (stat.isFile() && /\.(js|jsx|ts|tsx|cjs|mjs)$/.test(fullPath)) {
          results.push(fullPath);
        }
      } catch (err) {
        continue;
      }
    }
  } catch (err) {
    console.warn(`[!] Warning: Unable to read directory ${dir}`);
  }
  return results;
}

/**
 * Package name validation - filter out scoped packages and built-ins
 */
function isValidPackageName(name) {
  if (name.startsWith('.') || 
      name.startsWith('/') ||
    //  name.startsWith('@') ||  // Filter out scoped packages
      name.startsWith('node:') ||
      NODE_BUILTIN_MODULES.has(name)) {
    return false;
  }
  
    const skipPatterns = [
    /^https?:\/\//, // URLs
    /^\.\.?\//,     // Relative paths
    /^[a-z]:/i,     // Windows drive letters
    /^\#/,           // Import maps/package imports
    /^file:\/\//,   // File URLs
  ];
  
  return !skipPatterns.some(pattern => pattern.test(name));
}

/**
 * Normalize package names
 */
function normalizePackageName(packageName) {
  return packageName.split('/')[0];
}

/**
 * Extract imports from file using AST parsing
 */
async function extractImports(filePath) {
  const pkgNames = [];
  let code;
  
  try {
    code = await fs.readFile(filePath, 'utf8');
  } catch (err) {
    return pkgNames;
  }
  
  let ast;
  try {
    ast = parser.parse(code, {
      sourceType: 'module',
      plugins: [
        'jsx', 
        'typescript', 
        'decorators-legacy',
        'classProperties',
        'classPrivateProperties',
        'dynamicImport'
      ],
      errorRecovery: true,
    });
  } catch (err) {
    return pkgNames;
  }

  traverse(ast, {
    ImportDeclaration(path) {
      const source = path.node.source && path.node.source.value;
      if (source && typeof source === 'string') {
        pkgNames.push(source);
      }
    },
    
    CallExpression(path) {
      const callee = path.node.callee;
      const args = path.node.arguments;
      
      if (
        callee.type === 'Identifier' &&
        callee.name === 'require' &&
        args.length > 0 &&
        args[0].type === 'StringLiteral'
      ) {
        pkgNames.push(args[0].value);
      }
      else if (
        callee.type === 'Import' &&
        args.length > 0 &&
        args[0].type === 'StringLiteral'
      ) {
        pkgNames.push(args[0].value);
      }
    },
    
    ExportNamedDeclaration(path) {
      if (path.node.source) {
        const source = path.node.source.value;
        if (source && typeof source === 'string') {
          pkgNames.push(source);
        }
      }
    },
    
    ExportAllDeclaration(path) {
      const source = path.node.source && path.node.source.value;
      if (source && typeof source === 'string') {
        pkgNames.push(source);
      }
    }
  });

  return pkgNames;
}

/**
 * Track package occurrences with file paths
 */
function trackPackageOccurrence(rawPackageName, filePath) {
  const normalizedName = normalizePackageName(rawPackageName);
  if (!isValidPackageName(normalizedName)) return;
  
  if (!packageOccurrences.has(normalizedName)) {
    packageOccurrences.set(normalizedName, new Set());
  }
  packageOccurrences.get(normalizedName).add(filePath);
}

/**
 * Check package availability using HTTPS (reliable method)
 */
function checkPackageAvailability(name) {
  return new Promise((resolve) => {
    const url = `https://registry.npmjs.org/${encodeURIComponent(name)}`;
    
    const req = https.get(url, (res) => {
      // If status is 404, package is available
      if (res.statusCode === 404) {
        resolve({ name, status: 'Available', error: null });
      } else {
        // Any other status means package exists
        resolve({ name, status: 'Taken', error: null });
      }
    });
    
    req.setTimeout(10000, () => {
      req.destroy();
      resolve({ name, status: 'Error', error: 'Request timeout' });
    });
    
    req.on('error', (err) => {
      resolve({ name, status: 'Error', error: err.message });
    });
  });
}

/**
 * Check multiple packages with concurrency control
 */
async function checkPackagesBatch(packageNames) {
  const results = [];
  const BATCH_SIZE = 3;
  
  for (let i = 0; i < packageNames.length; i += BATCH_SIZE) {
    const batch = packageNames.slice(i, i + BATCH_SIZE);
    const batchPromises = batch.map(name => checkPackageAvailability(name));
    
    const batchResults = await Promise.all(batchPromises);
    results.push(...batchResults);
    
    if (i + BATCH_SIZE < packageNames.length) {
      await new Promise(resolve => setTimeout(resolve, 200));
    }
  }
  
  return results;
}

/**
 * Generate table format for console and file output
 */
function generateTable(data, columns) {
  // Calculate column widths
  const colWidths = columns.map(col => 
    Math.max(col.length, ...data.map(row => String(row[col] || '').length))
  );

  // Create header
  let table = '';
  table += columns.map((col, i) => col.padEnd(colWidths[i])).join(' | ') + '\n';
  table += columns.map((col, i) => '-'.repeat(colWidths[i])).join('-|-') + '\n';

  // Create rows
  data.forEach(row => {
    table += columns.map((col, i) => String(row[col] || '').padEnd(colWidths[i])).join(' | ') + '\n';
  });

  return table;
}

/**
 * Generate output only when available packages are found
 */
async function generateOutput(availablePackages, allResults) {
  // Show console output - simple table
  const nameColWidth = Math.max(...allResults.map(r => r.name.length), 12) + 2;
  let consoleOutput = '';
  consoleOutput += `${'Package Name'.padEnd(nameColWidth)}Status\n`;
  consoleOutput += `${'-'.repeat(nameColWidth)}-------\n`;
  
  for (const result of allResults) {
    consoleOutput += `${result.name.padEnd(nameColWidth)}${result.status}`;
    if (result.error) {
      consoleOutput += ` (${result.error})`;
    }
    consoleOutput += '\n';
  }

  console.log(consoleOutput.trim());
  
  // Only create output file if there are available packages
  if (availablePackages.length > 0) {
    // Prepare data for table format
    const tableData = [];
    
    for (const pkgName of availablePackages.sort()) {
      const filePaths = Array.from(packageOccurrences.get(pkgName));
      filePaths.sort().forEach(filePath => {
//        const relativePath = path.relative(rootDir, filePath);
      const absolutePath = path.resolve(filePath); 
       tableData.push({
          'Package Name': pkgName,
          'File Path': absolutePath
        });
      });
    }

    // Generate table format
    const fileOutput = generateTable(tableData, ['Package Name', 'File Path']);
    
    await fs.writeFile(outputFile, fileOutput, 'utf8');
    console.log(`\n[+] Scan results saved to: ${outputFile}`);
  }
}

/**
 * Main execution function
 */
async function main() {
  try {
    await fs.access(rootDir);
  } catch (err) {
    console.error(`[!] Error: Directory does not exist: ${rootDir}`);
    process.exit(1);
  }

  // Step 1: Collect all files
  const allFiles = await findFiles(rootDir);
  if (allFiles.length === 0) {
    console.log('[!] No source files found.');
    return;
  }

  // Step 2: Extract all package names and track occurrences
  let totalImports = 0;
  
  for (const file of allFiles) {
    const packages = await extractImports(file);
    totalImports += packages.length;
    packages.forEach(pkg => trackPackageOccurrence(pkg, file));
  }

  // Step 3: Get unique package candidates
  const candidates = Array.from(packageOccurrences.keys());
  if (candidates.length === 0) {
    console.log('[!] No package names found to check.');
    return;
  }

  // Step 4: Check npm registry availability
  const results = await checkPackagesBatch(candidates);
  const availablePackages = results.filter(r => r.status === 'Available').map(r => r.name);

  // Step 5: Generate output
  await generateOutput(availablePackages, results);
}

// Run the main function
main().catch(err => {
  console.error('Error:', err);
  process.exit(1);
});
