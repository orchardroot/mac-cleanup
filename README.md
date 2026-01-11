# Mac Cleanup Script

A simple script to tidy up unneeded files on a Mac.

## Features

-   **Screenshot Management:**
    -   Move screenshots older than a specified number of days (default: 1 day) from the Desktop to a `Screenshots` folder.
    -   Delete screenshots older than a specified number of days (default: 1 day) from the Desktop.
-   **Delete Downloads:** Delete all files from the `Downloads` folder.
-   **Clear Caches:** Clear system and application caches.
-   **Delete Logs:** Delete old system and user log files.
-   **Clear Browser History:** Clear browsing history for Chrome, Safari, and Firefox.
-   **Flush DNS Cache:** Flush the DNS resolver cache.
-   **Empty Trash:** Empty the user's trash can.
-   **Run All Cleanup Tasks:** Execute a predefined set of cleanup actions.
-   **Interactive Mode:** Asks for confirmation before each action.
-   **Dry Run Mode:** Shows what the script *would* do without actually making any changes.
-   **Error Handling:** Includes checks for existing directories/files to prevent failures.

## Usage

```bash
./tidy_mac.sh [options]
```

### Options

-   `-s [days]`: **Move screenshots**. Move screenshots older than `days` (default: 1) to `~/Desktop/Screenshots`.
-   `-x [days]`: **Delete screenshots**. Delete screenshots older than `days` (default: 1) from the Desktop.
-   `-d`: **Delete Downloads**. Delete all files from your `Downloads` folder.
-   `-c`: **Clear Caches**. Clear system and application caches.
-   `-l`: **Delete Logs**. Delete old log files.
-   `-b`: **Clear Browser History**. Clear browser history for Chrome, Safari, and Firefox.
-   `-f`: **Flush DNS Cache**. Flush the DNS cache.
-   `-t`: **Empty Trash**. Empty the Trash.
-   `-a`: **Run All**. Executes `-d -c -l -b -f -t` (all cleanup tasks *except* screenshot actions).
-   `-i`: **Interactive Mode**. Asks for confirmation before each action.
-   `-n`: **Dry Run Mode**. Shows what would be done without actually performing actions.
-   `-h`: **Help**. Display this help message.

### Examples

-   To run all cleanup tasks in interactive mode:
    ```bash
    ./tidy_mac.sh -a -i
    ```
-   To see what cleaning the downloads folder and emptying the trash would do (dry run):
    ```bash
    ./tidy_mac.sh -n -d -t
    ```
-   To move screenshots older than 30 days and then clear caches:
    ```bash
    ./tidy_mac.sh -s 30 -c
    ```
-   To delete screenshots older than 7 days and flush DNS (interactive):
    ```bash
    ./tidy_mac.sh -x 7 -f -i
    ```
-   To display the help message:
    ```bash
    ./tidy_mac.sh -h
    ```

## Important Notes

-   If you run the script without any options, it will display the help message.
-   The script will ask for your password (`sudo`) for some actions (e.g., clearing system caches, deleting system logs, flushing DNS cache) as these require administrator privileges.
-   The script includes robust error handling; it will not fail if a file or directory doesn't exist (e.g., if a browser is not installed, it will simply skip clearing its history).
-   Screenshot actions (`-s` and `-x`) are *not* included in the `-a` (run all) option. You must explicitly choose to move or delete screenshots.
-   When using dry run mode (`-n`), no actual files will be deleted, moved, or changed. The script will only report what it *would* do.
-   When using interactive mode (`-i`), the script will pause and ask for your confirmation before executing each major step.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
