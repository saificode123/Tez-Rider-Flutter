import pathlib
import zipfile

# Set up paths
root = pathlib.Path(r'c:\Users\hyperlink\Downloads\FYP_FINAL3\FYP_FINAL3\FYP_Final2_Backup').resolve()
zip_path = pathlib.Path(r'c:\Users\hyperlink\Downloads\FYP_FINAL3\FYP_Final2_Backup.zip').resolve()

# Folders to exclude
exclude_dirs = {'build', '.dart_tool', '.git', '.idea', '.vscode'}

print(f"Zipping from: {root}")
print(f"Creating archive at: {zip_path}")

with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as z:
    for path in root.rglob('*'):
        if not path.is_file():
            continue
        
        # Determine relative path
        rel_path = path.relative_to(root)
        
        # Skip if any parent folder is in the exclude list
        if any(part in exclude_dirs for part in rel_path.parts):
            continue
        
        # Write to zip under a parent folder named 'FYP_Final2_Backup'
        archive_name = pathlib.Path('FYP_Final2_Backup') / rel_path
        z.write(path, str(archive_name))

print("Zip file created successfully with a parent directory!")
