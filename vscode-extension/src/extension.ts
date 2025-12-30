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
        // Wait for dart format to complete, then run our formatter
        setTimeout(async () => {
          await formatWithGoStyle(document);
        }, 500); // Delay to let dart format finish
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
    let cliPath = path.join(workspaceRoot, 'freezed_go_style', 'bin', 'freezed_go_style.dart');
    
    // If not found, try parent directory (for cases where test project is opened separately)
    if (!fs.existsSync(cliPath)) {
      const parentDir = path.dirname(workspaceRoot);
      const parentCliPath = path.join(parentDir, 'freezed_go_style', 'bin', 'freezed_go_style.dart');
      if (fs.existsSync(parentCliPath)) {
        workspaceRoot = parentDir;
        cliPath = parentCliPath;
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
      const result = await execAsync(`dart run "${cliPath}" -f "${filePath}"`, {
        cwd: workspaceRoot,
      });
      
      console.log('freezed_go_style output:', result.stdout);
      
      // Reload document to show changes
      // Read the file from disk and update the editor
      setTimeout(async () => {
        try {
          const editor = vscode.window.activeTextEditor;
          if (editor && editor.document.fileName === filePath) {
            // Read the formatted file from disk
            const formattedContent = fs.readFileSync(filePath, 'utf8');
            const currentContent = editor.document.getText();
            
            // Only update if content changed
            if (formattedContent !== currentContent) {
              const edit = new vscode.WorkspaceEdit();
              const fullRange = new vscode.Range(
                editor.document.positionAt(0),
                editor.document.positionAt(currentContent.length)
              );
              edit.replace(editor.document.uri, fullRange, formattedContent);
              await vscode.workspace.applyEdit(edit);
              console.log('Document updated with formatted content');
            }
          }
        } catch (updateError) {
          console.error('Error updating document:', updateError);
          // Fallback to revert
          await vscode.commands.executeCommand('workbench.action.files.revert');
        }
      }, 200);
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

