# Mac Cleanup Script

A simple script to tidy up unneeded files on a Mac.

## Features

- Move screenshots from the Desktop to a `Screenshots` folder.
- Delete all files from the `Downloads` folder.
- Clear system and application caches.
- Delete old log files.
- Clear browser history for Chrome, Safari, and Firefox.
- Flush the DNS cache.
- Error handling for when files or directories do not exist.

## Usage

```bash
./tidy_mac.sh [options]
```

### Options

- `-s`: Move screenshots to a `Screenshots` folder on your desktop instead of deleting them.
- `-d`: Delete all files from your `Downloads` folder.
- `-c`: Clear system and application caches.
- `-l`: Delete old log files.
- `-b`: Clear browser history for Chrome, Safari, and Firefox.
- `-f`: Flush the DNS cache.
- `-h`: Display the help message.

### Examples

- To move screenshots and clear caches:
  ```bash
  ./tidy_mac.sh -s -c
  ```
- To delete downloads and flush the DNS cache:
  ```bash
  ./tidy_mac.sh -d -f
  ```
- To see the help message:
  ```bash
  ./tidy_mac.sh -h
  ```

## Important Notes

- If you run the script without any options, it will display the help message.
- The script will ask for your password (`sudo`) for some actions like clearing system caches, deleting system logs, and flushing the DNS cache. This is because these actions require administrator privileges.
- The script now includes error handling, so it won't fail if a file or directory doesn't exist. For example, if you don't have Google Chrome installed, it will simply skip the step of clearing its history.
- The default action for screenshots is to delete them. If you want to move them, you must use the `-s` option.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
