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
    // Parse with a comprehensive plugin list (JS/TS, JSX, modern proposals):contentReference[oaicite:6]{index=6}:contentReference[oaicite:7]{index=7}
    ast = parser.parse(code, {
      sourceType: 'unambiguous',
      plugins: [
        'exportDefaultFrom',
        'decorators-legacy',
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
    });
  } catch (err) {
    console.warn(`Warning: Failed to parse ${filePath}: ${err.message}`);
    return pkgNames;
  }

  // Traverse the AST to find import/require statements:contentReference[oaicite:8]{index=8}:contentReference[oaicite:9]{index=9}
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

// Step 1: Collect all files
const allFiles = findFiles(rootDir);

// Step 2: Extract all package names from imports/requires
let allPackages = [];
for (const file of allFiles) {
  allPackages = allPackages.concat(extractImports(file));
}

// Step 3: Filter out scoped, relative, and absolute imports; normalize subpaths
let candidates = allPackages
  .filter(name => {
    // Skip relative or absolute paths and scoped packages
    return !name.startsWith('.') && !name.startsWith('/') && !name.startsWith('@');
  })
  .map(name => {
    // If name has a slash (like lodash/map), take only the part before the slash
    const slashIndex = name.indexOf('/');
    return slashIndex > -1 ? name.substring(0, slashIndex) : name;
  });

// Step 4: Deduplicate package names
candidates = Array.from(new Set(candidates));

// Step 5: Check npm registry availability via HTTPS requests
// We'll collect results as { name, status } objects
const results = [];
let remaining = candidates.length;
if (remaining === 0) {
  console.log('No package names found to check.');
  process.exit(0);
}

candidates.forEach(name => {
  // Query registry.npmjs.org for the package name
  const url = `https://registry.npmjs.org/${encodeURIComponent(name)}`;
  https.get(url, (res) => {
    // If 404 => Not Found => Available; else Taken
    const status = (res.statusCode === 404) ? 'Available' : 'Taken';
    results.push({ name, status });
    remaining--;
    if (remaining === 0) {
      // All requests done, output the table
      // Sort results by name for consistency
      results.sort((a, b) => a.name.localeCompare(b.name));

      // Prepare fixed-width table output
      const nameColWidth = Math.max(...results.map(r => r.name.length), 12) + 2;
      let output = '';
      output += `${'Package Name'.padEnd(nameColWidth)}Status\n`;
      output += `${'-'.repeat(nameColWidth)}-------\n`;
      for (const {name, status} of results) {
        output += `${name.padEnd(nameColWidth)}${status}\n`;
      }
      // Print to console
      console.log(output.trim());
      // Save to output.txt
      fs.writeFileSync('output.txt', output, 'utf8');
    }
  }).on('error', (err) => {
    console.error(`Error checking ${name}: ${err.message}`);
    remaining--;
  });
});
