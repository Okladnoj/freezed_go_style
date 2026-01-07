import * as vscode from 'vscode';
import { exec } from 'child_process';
import { promisify } from 'util';
import * as path from 'path';
import * as fs from 'fs';

const execAsync = promisify(exec);

let isFormatting = false;

// Create output channel
const outputChannel = vscode.window.createOutputChannel('Freezed GoStyle');

export function activate(context: vscode.ExtensionContext) {
  outputChannel.appendLine('Freezed GoStyle extension is now active!');

  // Hook into document save to format after dart format
  context.subscriptions.push(
    vscode.workspace.onDidSaveTextDocument(async (document) => {
      outputChannel.appendLine(`Document saved: ${document.fileName}`);
      if (document.languageId === 'dart' && !isFormatting) {
        outputChannel.appendLine('Document is Dart file, checking for @FreezedGoStyle...');
        // Quick check if file contains @FreezedGoStyle annotation
        const content = document.getText();
        if (!content.includes('@FreezedGoStyle')) {
          outputChannel.appendLine('No @FreezedGoStyle annotation found, skipping');
          return; // Skip if no annotation found
        }

        outputChannel.appendLine('@FreezedGoStyle found, starting format...');
        // Format file after dart format has run
        await formatWithGoStyle(document, context);
      } else {
        if (document.languageId !== 'dart') {
          outputChannel.appendLine(`Document is not Dart (${document.languageId}), skipping`);
        }
        if (isFormatting) {
          outputChannel.appendLine('Already formatting, skipping');
        }
      }
    })
  );

  // Register command for manual formatting
  const formatCommand = vscode.commands.registerCommand(
    'freezed-go-style.format',
    async () => {
      const editor = vscode.window.activeTextEditor;
      if (editor && editor.document.languageId === 'dart') {
        await formatWithGoStyle(editor.document, context);
      }
    }
  );
  context.subscriptions.push(formatCommand);

  // Register as document formatter to intercept format commands
  const formatter = vscode.languages.registerDocumentFormattingEditProvider(
    'dart',
    {
      async provideDocumentFormattingEdits(
        document: vscode.TextDocument,
        options: vscode.FormattingOptions,
        token: vscode.CancellationToken
      ): Promise<vscode.TextEdit[]> {
        // Quick check if file contains @FreezedGoStyle annotation
        const content = document.getText();
        if (!content.includes('@FreezedGoStyle')) {
          return []; // Let default formatter handle it
        }

        // First, run standard dart format
        try {
          const filePath = document.fileName;
          await execAsync(`dart format "${filePath}"`);
        } catch (e) {
          outputChannel.appendLine(`dart format error: ${e}`);
        }

        // Then run our formatter
        await formatWithGoStyle(document, context);

        // Return empty array - our formatter modifies file directly
        // VS Code will reload the document
        return [];
      }
    }
  );
  context.subscriptions.push(formatter);
}

async function formatWithGoStyle(document: vscode.TextDocument, context: vscode.ExtensionContext): Promise<void> {
  outputChannel.appendLine('formatWithGoStyle called');
  if (isFormatting) {
    outputChannel.appendLine('Already formatting, returning');
    return;
  }

  const filePath = document.fileName;
  outputChannel.appendLine(`Formatting file: ${filePath}`);
  if (!filePath || !filePath.endsWith('.dart')) {
    outputChannel.appendLine('File is not a Dart file, returning');
    return;
  }

  isFormatting = true;

  try {
    // Find freezed_go_style CLI tool
    // Try multiple locations: relative to file, workspace, and parent directories
    let cliPath: string | null = null;
    let useDartRun = false;
    let workingDir = path.dirname(filePath);

    // Search paths to try (in order of preference)
    const searchPaths: string[] = [];

    // 0. Bundled CLI (if packaged with the extension)
    // We expect the 'cli' folder to be at the root of the extension installation
    searchPaths.push(path.join(context.extensionPath, 'cli', 'bin', 'freezed_go_style.dart'));

    // 1. Relative to file being formatted (go up directories looking for freezed_go_style)
    let currentDir = path.dirname(filePath);
    for (let i = 0; i < 5; i++) {
      searchPaths.push(path.join(currentDir, 'freezed_go_style', 'bin', 'freezed_go_style.dart'));
      searchPaths.push(path.join(currentDir, 'freezed_go_style', 'bin', 'freezed_go_style'));
      currentDir = path.dirname(currentDir);
    }

    // 2. Workspace root and parent directories
    const workspaceFolder = vscode.workspace.getWorkspaceFolder(document.uri);
    if (workspaceFolder) {
      const workspaceRoot = workspaceFolder.uri.fsPath;

      // Check directly in bin folder of workspace (for development mode)
      searchPaths.push(path.join(workspaceRoot, 'bin', 'freezed_go_style.dart'));
      searchPaths.push(path.join(workspaceRoot, 'bin', 'freezed_go_style'));

      // Check in subdirectory (monorepo style)
      searchPaths.push(path.join(workspaceRoot, 'freezed_go_style', 'bin', 'freezed_go_style.dart'));
      searchPaths.push(path.join(workspaceRoot, 'freezed_go_style', 'bin', 'freezed_go_style'));

      // Check parent directories (up to 5 levels) for monorepo setups
      let parentDir = workspaceRoot;
      for (let i = 0; i < 5; i++) {
        parentDir = path.dirname(parentDir);
        searchPaths.push(path.join(parentDir, 'freezed_go_style', 'bin', 'freezed_go_style.dart'));
        searchPaths.push(path.join(parentDir, 'freezed_go_style', 'bin', 'freezed_go_style'));
        // Also check in common monorepo structures
        searchPaths.push(path.join(parentDir, 'packages', 'freezed_go_style', 'bin', 'freezed_go_style.dart'));
        searchPaths.push(path.join(parentDir, 'packages', 'freezed_go_style', 'bin', 'freezed_go_style'));
        searchPaths.push(path.join(parentDir, 'tools', 'freezed_go_style', 'bin', 'freezed_go_style.dart'));
        searchPaths.push(path.join(parentDir, 'tools', 'freezed_go_style', 'bin', 'freezed_go_style'));
      }
    }

    // 4. Check for dart package executable (if installed as dependency)
    // Dependencies usually have their bins exposed in .dart_tool/maven/bin ... wait no, standard dart projects
    // We can try running `dart run freezed_go_style` directly. If it's in pubspec dependencies, this works.

    outputChannel.appendLine(`Scanning for freezed_go_style...`);

    // Check if we can run via 'dart run' (implies it's in pubspec dependencies)
    // We test this by trying to check version or help
    if (!cliPath) {
      try {
        outputChannel.appendLine('Checking if available via "dart run"...');
        // We use the workspace root as CWD
        let runCwd = path.dirname(filePath);
        const workspaceFolder = vscode.workspace.getWorkspaceFolder(document.uri);
        if (workspaceFolder) {
          runCwd = workspaceFolder.uri.fsPath;
        }

        // Try to resolve the package using 'dart pub deps' or simply trying to run it?
        // Actually, best way is to check pubspec.lock or pubspec.yaml for the dependency
        const pubspecPath = path.join(runCwd, 'pubspec.yaml');
        if (fs.existsSync(pubspecPath)) {
          const pubspecContent = fs.readFileSync(pubspecPath, 'utf8');
          if (pubspecContent.includes('freezed_go_style')) {
            outputChannel.appendLine('Found freezed_go_style in pubspec.yaml');
            // It is a dependency. We can run it via 'dart run freezed_go_style:main' or just 'dart run freezed_go_style'
            // We need to return a special flag or just handle execution differently.
            // Let's set a flag that we use 'dart run' command style.
            cliPath = 'freezed_go_style'; // Logic marker
            useDartRun = true;
            workingDir = runCwd;
          } else {
            outputChannel.appendLine('freezed_go_style NOT found in pubspec.yaml');
          }
        }
      } catch (e) {
        outputChannel.appendLine(`Error checking pubspec: ${e}`);
      }
    }

    // If it wasn't found in pubspec, continue searching other paths
    if (!cliPath || cliPath !== 'freezed_go_style') {
      // 3. Try to find via which/where (if installed globally)
      try {
        const { stdout } = await execAsync('which freezed_go_style 2>/dev/null || where freezed_go_style 2>/dev/null || echo ""');
        if (stdout && stdout.trim()) {
          searchPaths.push(stdout.trim());
        }
      } catch {
        // Ignore errors
      }

      // 4. Try dart pub global run (if installed globally)
      if (!cliPath || cliPath !== 'freezed_go_style') {
        try {
          const workspaceFolder = vscode.workspace.getWorkspaceFolder(document.uri);
          if (workspaceFolder) {
            const runCwd = workspaceFolder.uri.fsPath;
            // Test if we can run it via pub global
            try {
              const { stdout, stderr } = await execAsync('dart pub global run freezed_go_style --help 2>&1', { cwd: runCwd, timeout: 3000 });
              const output = (stdout || '') + (stderr || '');
              if (output && !output.includes('is not installed') && !output.includes('not found') && !output.includes('Could not find')) {
                outputChannel.appendLine('Found freezed_go_style via dart pub global');
                cliPath = 'freezed_go_style';
                useDartRun = false; // Use 'dart pub global run' instead
                workingDir = runCwd;
                // We'll use 'dart pub global run' command format later
              }
            } catch (e: any) {
              // Ignore timeout and other errors
              outputChannel.appendLine(`dart pub global check failed: ${e.message || e}`);
            }
          }
        } catch {
          // Ignore errors
        }
      }

      // Find first existing path
      for (const searchPath of searchPaths) {
        if (fs.existsSync(searchPath)) {
          const absolutePath = path.resolve(searchPath);
          const parentDir = path.dirname(absolutePath);

          if (path.basename(parentDir) === 'bin') {
            // If file is in bin/ folder, project root is one level up
            workingDir = path.dirname(parentDir);
            if (absolutePath.endsWith('.dart')) {
              useDartRun = true;
              // For 'dart run', use relative path from project root
              cliPath = path.relative(workingDir, absolutePath).replace(/\\/g, '/');
            } else {
              useDartRun = false;
              cliPath = absolutePath;
            }
          } else {
            // If folder is not bin/, use default logic
            cliPath = absolutePath;
            workingDir = parentDir;
            useDartRun = absolutePath.endsWith('.dart');
          }
          break;
        }
      }
    }

    outputChannel.appendLine(`Looking for CLI in: ${searchPaths.slice(0, 5).join(', ')}...`);
    outputChannel.appendLine(`File path: ${filePath}`);

    if (!cliPath) {
      outputChannel.appendLine('ERROR: freezed_go_style CLI not found.');

      const selection = await vscode.window.showErrorMessage(
        `Freezed GoStyle: CLI not found. Do you want to add it to dependencies?`,
        'Yes', 'No'
      );

      if (selection === 'Yes') {
        try {
          let runCwd = path.dirname(filePath);
          const workspaceFolder = vscode.workspace.getWorkspaceFolder(document.uri);
          if (workspaceFolder) {
            runCwd = workspaceFolder.uri.fsPath;
          }

          outputChannel.appendLine(`Running 'dart pub add freezed_go_style' in ${runCwd}`);
          await execAsync('dart pub add freezed_go_style', { cwd: runCwd });

          vscode.window.showInformationMessage('Successfully added freezed_go_style. Try saving the file again.');
        } catch (e: any) {
          vscode.window.showErrorMessage(`Failed to add dependency: ${e.message}`);
        }
      }
      return;
    }

    outputChannel.appendLine(`CLI found at: ${cliPath}`);
    outputChannel.appendLine(`Using dart run: ${useDartRun}`);

    // Run freezed_go_style (dart format should have already run)
    try {
      let command: string;
      if (cliPath === 'freezed_go_style' && !useDartRun) {
        // Use dart pub global run
        command = `dart pub global run freezed_go_style -f "${filePath}"`;
      } else if (useDartRun) {
        command = `dart run "${cliPath}" -f "${filePath}"`;
      } else {
        command = `"${cliPath}" -f "${filePath}"`;
      }

      outputChannel.appendLine(`Running command: ${command}`);
      outputChannel.appendLine(`Working directory: ${workingDir}`);

      const result = await execAsync(command, {
        cwd: workingDir,
      });

      outputChannel.appendLine(`freezed_go_style output: ${result.stdout}`);

      // Reload document from disk (CLI already saved the formatted file)
      try {
        // Use revert to reload from disk - this is fast and simple
        await vscode.commands.executeCommand('workbench.action.files.revert', document.uri);
        outputChannel.appendLine('Document reloaded with formatted content');
      } catch (updateError) {
        outputChannel.appendLine(`Error reloading document: ${updateError}`);
      }
    } catch (error: any) {
      // Log errors for debugging
      outputChannel.appendLine(`freezed_go_style error: ${error.message}`);
      if (error.stderr) {
        outputChannel.appendLine(`freezed_go_style stderr: ${error.stderr}`);
      }
    }
  } catch (error) {
    outputChannel.appendLine(`Error in freezed_go_style extension: ${error}`);
  } finally {
    isFormatting = false;
  }
}


