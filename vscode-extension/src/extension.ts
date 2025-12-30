import * as vscode from 'vscode';
import { exec } from 'child_process';
import { promisify } from 'util';
import * as path from 'path';
import * as fs from 'fs';

const execAsync = promisify(exec);

let isFormatting = false;

export function activate(context: vscode.ExtensionContext) {
  console.log('Freezed GoStyle extension is now active!');

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
        await formatWithGoStyle(document);
      }
    })
  );

  // Register command for manual formatting
  const formatCommand = vscode.commands.registerCommand(
    'freezed-go-style.format',
    async () => {
      const editor = vscode.window.activeTextEditor;
      if (editor && editor.document.languageId === 'dart') {
        await formatWithGoStyle(editor.document);
      }
    }
  );
  context.subscriptions.push(formatCommand);
}

async function formatWithGoStyle(document: vscode.TextDocument): Promise<void> {
  if (isFormatting) {
    return;
  }

  const filePath = document.fileName;
  if (!filePath || !filePath.endsWith('.dart')) {
    return;
  }

  isFormatting = true;

  try {
    // Find freezed_go_style CLI tool in workspace
    const workspaceFolder = vscode.workspace.getWorkspaceFolder(document.uri);
    if (!workspaceFolder) {
      return;
    }

    // Look for freezed_go_style in workspace root or parent directory
    let workspaceRoot = workspaceFolder.uri.fsPath;
    
    // Try to find compiled executable first (much faster)
    let cliPath = path.join(workspaceRoot, 'freezed_go_style', 'bin', 'freezed_go_style');
    let useDartRun = false;
    
    // If not found, try parent directory
    if (!fs.existsSync(cliPath)) {
      const parentDir = path.dirname(workspaceRoot);
      const parentCliPath = path.join(parentDir, 'freezed_go_style', 'bin', 'freezed_go_style');
      if (fs.existsSync(parentCliPath)) {
        workspaceRoot = parentDir;
        cliPath = parentCliPath;
      }
    }
    
    // If executable not found, fall back to dart run (slower)
    if (!fs.existsSync(cliPath)) {
      cliPath = path.join(workspaceRoot, 'freezed_go_style', 'bin', 'freezed_go_style.dart');
      useDartRun = true;
      
      if (!fs.existsSync(cliPath)) {
        const parentDir = path.dirname(workspaceRoot);
        const parentCliPath = path.join(parentDir, 'freezed_go_style', 'bin', 'freezed_go_style.dart');
        if (fs.existsSync(parentCliPath)) {
          workspaceRoot = parentDir;
          cliPath = parentCliPath;
        }
      }
    }
    
    console.log('Looking for CLI at:', cliPath);
    console.log('Workspace root:', workspaceRoot);
    console.log('File path:', filePath);
    
    if (!fs.existsSync(cliPath)) {
      console.error('freezed_go_style CLI not found at:', cliPath);
      vscode.window.showErrorMessage(`Freezed GoStyle: CLI not found. Expected at ${cliPath}`);
      return;
    }
    
    console.log('CLI found, running formatter...');

    // Run freezed_go_style (dart format should have already run)
    try {
      const command = useDartRun 
        ? `dart run "${cliPath}" -f "${filePath}"`
        : `"${cliPath}" -f "${filePath}"`;
      
      console.log('Running command:', command);
      
      const result = await execAsync(command, {
        cwd: workspaceRoot,
      });
      
      console.log('freezed_go_style output:', result.stdout);
      
      // Reload document from disk (CLI already saved the formatted file)
      try {
        // Use revert to reload from disk - this is fast and simple
        await vscode.commands.executeCommand('workbench.action.files.revert', document.uri);
        console.log('Document reloaded with formatted content');
      } catch (updateError) {
        console.error('Error reloading document:', updateError);
      }
    } catch (error: any) {
      // Log errors for debugging
      console.error('freezed_go_style error:', error.message);
      if (error.stderr) {
        console.error('freezed_go_style stderr:', error.stderr);
      }
    }
  } catch (error) {
    console.error('Error in freezed_go_style extension:', error);
  } finally {
    isFormatting = false;
  }
}

export function deactivate() {}

