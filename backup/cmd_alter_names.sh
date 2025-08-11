#!/bin/bash

# A script to rename files in the current directory.
# It changes filenames like "asd.qwe.zxc.asd.2024" to "asd qwe zxc asd (2024)".
# It ignores subdirectories.

# Check if a directory path was provided as an argument.
# '$#' holds the number of command-line arguments.
if [[ $# -eq 0 ]]; then
    echo "Usage: $0 /path/to/your/directory"
    exit 1
fi

# Store the first command-line argument in a variable.
# '$1' refers to the first argument.
target_dir="$1"

# Check if the provided path is a valid directory.
# The '-d' test returns true if the item exists and is a directory.
if [[ ! -d "$target_dir" ]]; then
    echo "Error: Directory not found or is not a directory."
    exit 1
fi

# Loop through all files in the specified directory.
# We use "$target_dir/*" to get all items inside the directory.
for filename in "$target_dir"/*; do
    # Check if the current item is a regular file.
    # The '-f' test returns true if the item exists and is a regular file.
    if [[ -f "$filename" ]]; then
        # Use 'basename' to get the filename without its extension.
        base="${filename%.*}"
        # Use 'basename' with the full filename to get the extension.
        ext="${filename##*.}"

        # Replace all dots in the base filename with spaces.
        new_base=$(echo "$base" | sed 's/\./ /g')

        # Use a regular expression to find a 4-digit year at the end of the string.
        # The '(....)' part captures the 4-digit year.
        # We then replace the matched year with the year inside parentheses.
        # '$' ensures the match is at the end of the string.
        if [[ $new_base =~ (.*)[[:space:]]([0-9]{4})$ ]]; then
            # The 'BASH_REMATCH' array holds the results of the regex match.
            # BASH_REMATCH[1] is the part of the string before the year.
            # BASH_REMATCH[2] is the year itself.
            new_base="${BASH_REMATCH[1]} (${BASH_REMATCH[2]})"
        fi

        # Check if the filename has changed to avoid renaming the same file.
        # The '!= "$filename"' check prevents errors if the filename is already in the new format.
        if [[ "$new_base.$ext" != "$filename" ]]; then
            # Use 'mv' to rename the file.
            # We use double quotes to handle filenames with spaces.
            echo "Renaming '$filename' to '$new_base.$ext'"
            mv "$filename" "$new_base.$ext"
        fi
    fi
done

echo "Renaming complete."
