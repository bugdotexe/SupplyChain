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

const rootDir = path.resolve(process.argv[2]);
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
    console.warn(`Warning: Unable to read directory ${dir}`);
  }
  return results;
}

/**
 * Enhanced package name validation
 */
function isValidPackageName(name) {
  // Skip relative/absolute paths and Node.js built-ins
  if (name.startsWith('.') || 
      name.startsWith('/') ||
      //name.startsWith('@') ||
      name.startsWith('node:') ||
      NODE_BUILTIN_MODULES.has(name)) {
    return false;
  }
  
  // Skip common non-package imports
      const skipPatterns = [
    /^https?:\/\//, // URLs
    /^\.\.?\//,     // Relative paths
    /^[a-z]:/i,     // Windows drive letters
    /^\#/,           // Import maps/package imports
    /^file:\/\//,   // File URLs
  ];
  
  // Filter out invalid single characters and special patterns
  if (/^[^a-zA-Z0-9@]/.test(name) || /^[*~!@#$%^&()+={\}[\]|:;"'<>,?/`]$/.test(name)) {
    return false;
  }
  
  // Additional npm package naming validation
  if (name.length === 0 || name.length > 214) return false;
  if (!/^[a-zA-Z0-9][a-zA-Z0-9._-]*$/.test(name)) return false;
  
  return !skipPatterns.some(pattern => pattern.test(name));
}

/**
 * Enhanced package name normalization with slash counting
 */
function normalizePackageName(packageName) {
  // Handle scoped packages (@scope/name) - always allow any number of slashes
  if (packageName.startsWith('@') && packageName.includes('/')) {
    const parts = packageName.split('/');
    return parts.slice(0, 2).join('/');
  }
  
  // For non-scoped packages, count the slashes
  if (!packageName.startsWith('@')) {
    const slashCount = (packageName.match(/\//g) || []).length;
    
    // If there are 2 or more slashes, it's likely a local path
    if (slashCount >= 2) {
      return null;
    }
    
    // If there's exactly 1 slash, it's likely a deep import (like lodash/map)
    // Extract just the package name part
    return packageName.split('/')[0];
  }
  
  // For regular packages without slashes
  return packageName;
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
  
  // If normalization returns null, it's a local path, not an npm package
  if (normalizedName === null || !isValidPackageName(normalizedName)) return;
  
  if (!packageOccurrences.has(normalizedName)) {
    packageOccurrences.set(normalizedName, new Set());
  }
  packageOccurrences.get(normalizedName).add(filePath);
}

/**
 * Check package availability using HTTPS
 */
function checkPackageAvailability(name) {
  return new Promise((resolve) => {
    const url = `https://registry.npmjs.org/${encodeURIComponent(name)}`;
    
    const req = https.get(url, (res) => {
      if (res.statusCode === 404) {
        resolve({ name, status: 'Available', error: null });
      } else {
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
 * Generate clean table format for output
 */
function generateCleanTable(data) {
  if (data.length === 0) return '';
  
  // Calculate column widths
  const pkgNameWidth = Math.max('Package Name'.length, ...data.map(row => row.packageName.length));
  const filePathWidth = Math.max('File Path'.length, ...data.map(row => row.filePath.length));
  
  // Create header
  let table = '';
  table += `${'Package Name'.padEnd(pkgNameWidth)} | ${'File Path'.padEnd(filePathWidth)}\n`;
  table += `${'-'.repeat(pkgNameWidth)}-|-${'-'.repeat(filePathWidth)}\n`;
  
  // Create rows
  data.forEach(row => {
    table += `${row.packageName.padEnd(pkgNameWidth)} | ${row.filePath}\n`;
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
    // Prepare data for clean table format
    const tableData = [];
    
    for (const pkgName of availablePackages.sort()) {
      const filePaths = Array.from(packageOccurrences.get(pkgName));
      filePaths.sort().forEach(filePath => {
        const absolutePath = path.resolve(filePath);
        tableData.push({
          packageName: pkgName,
          filePath: absolutePath
        });
      });
    }

    // Generate clean table format
    const fileOutput = generateCleanTable(tableData);
    
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
    console.error(`Error: Directory does not exist: ${rootDir}`);
    process.exit(1);
  }

  console.log(`[*] Scanning directory: ${rootDir}`);

  // Step 1: Collect all files
  const allFiles = await findFiles(rootDir);
  if (allFiles.length === 0) {
    console.log('No source files found.');
    return;
  }
  console.log(`[*] Found ${allFiles.length} files to analyze`);

  // Step 2: Extract all package names and track occurrences
  let totalImports = 0;
  
  for (const file of allFiles) {
    const packages = await extractImports(file);
    totalImports += packages.length;
    packages.forEach(pkg => trackPackageOccurrence(pkg, file));
  }

  console.log(`[*] Extracted ${totalImports} import statements`);

  // Step 3: Get unique package candidates
  const candidates = Array.from(packageOccurrences.keys());
  if (candidates.length === 0) {
    console.log('No package names found to check.');
    return;
  }

  console.log(`[*] Found ${candidates.length} package candidates to check`);

  // Step 4: Check npm registry availability
  console.log('[*] Checking package availability...');
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
