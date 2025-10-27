#!/usr/bin/env node
/**
 * Script to scan a directory for JS/TS files, extract imported package names,
 * and check npm registry for package availability.
 */

// Node core modules
const fs = require('fs');
const path = require('path');
const https = require('https');

// Babel for parsing and traversing AST
const parser = require('@babel/parser');
const traverse = require('@babel/traverse').default;

// Get target directory from CLI arguments
const targetDir = process.argv[2];
if (!targetDir) {
  console.error('Usage: node script.js <target-directory>');
  process.exit(1);
}

// Recursively collect .js and .ts files from a directory
function getAllFiles(dir) {
  let results = [];
  // Read all entries (files and folders) in the directory
  fs.readdirSync(dir).forEach(file => {
    const fullPath = path.join(dir, file);
    const stat = fs.lstatSync(fullPath);
    if (stat.isDirectory()) {
      // If it's a directory, recurse into it
      results = results.concat(getAllFiles(fullPath));
    } else if (stat.isFile() && (fullPath.endsWith('.js') || fullPath.endsWith('.ts'))) {
      // If it's a JS/TS file, add it to results
      results.push(fullPath);
    }
  });
  return results;
}

// Extract import/require package names from a single file
function extractPackagesFromFile(filePath) {
  const code = fs.readFileSync(filePath, 'utf8');
  // Parse the file content into an AST (enable module, JSX, TS, dynamic import)
  const ast = parser.parse(code, {
    sourceType: 'module',
    plugins: ['jsx', 'typescript', 'dynamicImport']
  });

  const packages = [];
  traverse(ast, {
    // import ... from 'pkg' and import 'pkg'
    ImportDeclaration({ node }) {
      const value = node.source.value;
      if (typeof value === 'string') {
        packages.push(value);
      }
    },
    // require('pkg')
    CallExpression(path) {
      const callee = path.get('callee');
      // Check for require(...)
      if (callee.isIdentifier({ name: 'require' })) {
        const arg = path.node.arguments[0];
        if (arg && arg.type === 'StringLiteral') {
          packages.push(arg.value);
        }
      }
      // Dynamic import (import('pkg'))
      if (path.node.callee.type === 'Import') {
        const arg = path.node.arguments[0];
        if (arg && arg.type === 'StringLiteral') {
          packages.push(arg.value);
        }
      }
    }
  });

  return packages;
}

// Filter and normalize package names (remove scoped, relative, subpaths)
function normalizePackageNames(names) {
  const set = new Set();
  for (let name of names) {
    if (!name) continue;
    // Skip scoped packages (@scope/pkg) and relative/absolute paths (./ or /)
    if (name.startsWith('@') || name.startsWith('.') || name.startsWith('/')) {
      continue;
    }
    // If subpath (pkg/sub), take only base
    if (name.includes('/')) {
      name = name.split('/')[0];
    }
    set.add(name);
  }
  return Array.from(set);
}

// Check npm registry for availability of a package name
function checkPackageAvailability(pkgName) {
  return new Promise(resolve => {
    https.get(`https://registry.npmjs.org/${pkgName}`, (res) => {
      // If statusCode is 404, package is available; otherwise it's taken
      resolve({ name: pkgName, status: res.statusCode === 404 ? 'Available' : 'Taken' });
    }).on('error', (err) => {
      console.error(`Error checking ${pkgName}: ${err.message}`);
      resolve({ name: pkgName, status: 'Error' });
    });
  });
}

// Main execution flow
(function main() {
  // 1. Scan directory for files
  const files = getAllFiles(targetDir);

  // 2. Extract all raw package specifiers
  let rawPackages = [];
  for (const file of files) {
    rawPackages = rawPackages.concat(extractPackagesFromFile(file));
  }

  // 3. Filter, normalize, and deduplicate package names
  const packages = normalizePackageNames(rawPackages);

  // 4. Check availability for each package
  Promise.all(packages.map(checkPackageAvailability))
    .then(results => {
      // 5. Print formatted table
      const nameCol = 'Package';
      const statusCol = 'Status';
      const nameWidth = Math.max(
        nameCol.length, 
        ...results.map(r => r.name.length)
      );
      console.log(`${nameCol.padEnd(nameWidth)} | ${statusCol}`);
      console.log(`${'-'.repeat(nameWidth)}-|--------`);
      results.forEach(({name, status}) => {
        console.log(`${name.padEnd(nameWidth)} | ${status}`);
      });
    })
    .catch(err => {
      console.error('Error during processing:', err);
    });
})();
