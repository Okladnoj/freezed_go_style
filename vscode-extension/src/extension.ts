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
      if (document.languageId === 'dart' && !isFormatting) {
        // Quick check if file contains @FreezedGoStyle annotation
        const content = document.getText();
        if (!content.includes('@FreezedGoStyle')) {
          return; // Skip if no annotation found
        }

        // Format file after dart format has run
        await formatWithGoStyle(document, context);
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
}

async function formatWithGoStyle(document: vscode.TextDocument, context: vscode.ExtensionContext): Promise<void> {
  if (isFormatting) {
    return;
  }

  const filePath = document.fileName;
  if (!filePath || !filePath.endsWith('.dart')) {
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
      searchPaths.push(path.join(currentDir, 'freezed_go_style', 'bin', 'freezed_go_style'));
      searchPaths.push(path.join(currentDir, 'freezed_go_style', 'bin', 'freezed_go_style.dart'));
      currentDir = path.dirname(currentDir);
    }

    // 2. Workspace root
    const workspaceFolder = vscode.workspace.getWorkspaceFolder(document.uri);
    if (workspaceFolder) {
      const workspaceRoot = workspaceFolder.uri.fsPath;

      // Check directly in bin folder of workspace (for development mode)
      searchPaths.push(path.join(workspaceRoot, 'bin', 'freezed_go_style'));
      searchPaths.push(path.join(workspaceRoot, 'bin', 'freezed_go_style.dart'));

      // Check in subdirectory (monorepo style)
      searchPaths.push(path.join(workspaceRoot, 'freezed_go_style', 'bin', 'freezed_go_style'));
      searchPaths.push(path.join(workspaceRoot, 'freezed_go_style', 'bin', 'freezed_go_style.dart'));

      // Parent of workspace
      const parentDir = path.dirname(workspaceRoot);
      searchPaths.push(path.join(parentDir, 'freezed_go_style', 'bin', 'freezed_go_style'));
      searchPaths.push(path.join(parentDir, 'freezed_go_style', 'bin', 'freezed_go_style.dart'));
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

      // Find first existing path
      for (const searchPath of searchPaths) {
        if (fs.existsSync(searchPath)) {
          cliPath = searchPath;
          useDartRun = searchPath.endsWith('.dart');

          // If we found a dart script in a 'bin' folder, run from the package root (parent of 'bin')
          if (useDartRun && path.basename(path.dirname(searchPath)) === 'bin') {
            workingDir = path.dirname(path.dirname(searchPath));
          } else {
            workingDir = path.dirname(searchPath);
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
        `Freezed GoStyle: CLI not found. Do you want to add it to dev_dependencies?`,
        'Yes', 'No'
      );

      if (selection === 'Yes') {
        try {
          let runCwd = path.dirname(filePath);
          const workspaceFolder = vscode.workspace.getWorkspaceFolder(document.uri);
          if (workspaceFolder) {
            runCwd = workspaceFolder.uri.fsPath;
          }

          outputChannel.appendLine(`Running 'dart pub add --dev freezed_go_style' in ${runCwd}`);
          await execAsync('dart pub add --dev freezed_go_style', { cwd: runCwd });

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
      const command = useDartRun
        ? `dart run "${cliPath}" -f "${filePath}"`
        : `"${cliPath}" -f "${filePath}"`;

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


