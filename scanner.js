#!/usr/bin/env node
// scanner.js

const fs = require('fs').promises;
const path = require('path');
const glob = require('fast-glob');
const parser = require('@babel/parser');
const traverse = require('@babel/traverse').default;
const axios = require('axios');

/**
 * Finds all relevant JavaScript/TypeScript files in a directory.
 * @param {string} targetDir - The directory to scan.
 * @returns {Promise<string>} A list of file paths.
 */
async function findSourceFiles(targetDir) {
  const patterns = ['**/*.js', '**/*.mjs', '**/*.cjs', '**/*.ts', '**/*.jsx', '**/*.tsx'];
  const options = {
    cwd: targetDir,
    absolute: true,
    ignore: ['**/node_modules/**'],
  };
  return glob(patterns, options);
}

/**
 * Extracts package names from a single file using AST parsing.
 * @param {string} filePath - The path to the file to parse.
 * @returns {Promise<Set<string>>} A set of unique package names.
 */
async function extractPackagesFromFile(filePath) {
  const packages = new Set();
  try {
    const code = await fs.readFile(filePath, 'utf-8');
    const ast = parser.parse(code, {
      sourceType: 'module',
      plugins: ['jsx', 'typescript'],
      errorRecovery: true, // Attempt to parse even with syntax errors
    });

    traverse(ast, {
      ImportDeclaration(path) {
        packages.add(path.node.source.value);
      },
      CallExpression(path) {
        const callee = path.node.callee;
        const firstArg = path.node.arguments;
        if (
          callee.type === 'Identifier' &&
          callee.name === 'require' &&
          path.node.arguments.length > 0 &&
          firstArg && firstArg.type === 'StringLiteral'
        ) {
          packages.add(firstArg.value);
        } else if (callee.type === 'Import') { // For dynamic import()
          if (path.node.arguments.length > 0 && firstArg && firstArg.type === 'StringLiteral') {
            packages.add(firstArg.value);
          }
        }
      },
    });
  } catch (error) {
    console.warn(`[!] Skipping file due to parsing error: ${filePath}`);
  }
  return packages;
}

/**
 * Checks a list of package names against the npm registry.
 * @param {string} packageNames - An array of package names to check.
 * @returns {Promise<string>} A list of package names that are available.
 */
async function checkPackageAvailability(packageNames) {
  const availablePackages =;
  const requests = packageNames.map(name => {
    // Ignore relative paths and built-in modules
    if (name.startsWith('.') ||!name.includes('/')) {
        // A simple heuristic; more robust checking for built-ins might be needed
        if (['fs', 'path', 'http', 'https', 'os'].includes(name)) return Promise.resolve(null);
    }

    const encodedName = name.replace('/', '%2f');
    const url = `https://registry.npmjs.org/${encodedName}`;
    
    return axios.head(url) // Use HEAD request for efficiency
    .catch(error => {
        if (error.response && error.response.status === 404) {
          return name; // This is a potential vulnerability
        }
        return null; // Package exists or another error occurred
      });
  });

  const results = await Promise.all(requests);
  return results.filter(Boolean); // Filter out nulls
}

/**
 * Main function to orchestrate the scan.
 * @param {string} targetDir - The directory to scan.
 */
async function main() {
  const targetDir = process.argv[span_63](start_span)[span_63](end_span);
  if (!targetDir) {
    console.error('Usage: node scanner.js <directory-to-scan>');
    process.exit(1);
  }

  console.log(`[*] Starting scan on directory: ${targetDir}`);

  // 1. Discover files
  const files = await findSourceFiles(targetDir);
  console.log(`[+] Found ${files.length} source files to analyze.`);

  // 2. Extract packages
  const allPackages = new Set();
  const extractionPromises = files.map(file => extractPackagesFromFile(file));
  const results = await Promise.all(extractionPromises);
  results.forEach(packageSet => {
    packageSet.forEach(pkg => allPackages.add(pkg));
  });
  console.log(`[+] Extracted ${allPackages.size} unique package names.`);

  // 3. Verify availability
  const packageList = Array.from(allPackages);
  console.log('[*] Checking package availability on npm registry...');
  const vulnerablePackages = await checkPackageAvailability(packageList);

  // 4. Report results
  if (vulnerablePackages.length > 0) {
    console.log('\n--- POTENTIAL DEPENDENCY CONFUSION VULNERABILITIES FOUND ---');
    vulnerablePackages.forEach(pkg => {
      console.log(`  - ${pkg}`);
    });
    console.log('\nThese packages are used in the project but do not exist on the public npm registry.');
  } else {
    console.log('\n[+] No potential dependency confusion vulnerabilities found.');
  }
}

main().catch(console.error);
