"""Add Python user Scripts directory to Windows PATH (Windows only)."""

import os
import site
import sys


def get_scripts_dir():
    """Get the Python user Scripts directory."""
    # This is where pip installs console_scripts for --user installs
    user_scripts = os.path.join(site.getusersitepackages().rsplit("site-packages", 1)[0], "Scripts")
    if os.path.isdir(user_scripts):
        return user_scripts

    # Fallback: derive from sys.executable
    fallback = os.path.join(os.path.dirname(sys.executable), "Scripts")
    if os.path.isdir(fallback):
        return fallback

    return user_scripts  # Return the expected path even if it doesn't exist yet


def is_on_path(directory):
    """Check if a directory is already on the user's PATH."""
    path_dirs = os.environ.get("PATH", "").split(os.pathsep)
    return any(os.path.normcase(os.path.normpath(d)) == os.path.normcase(os.path.normpath(directory))
               for d in path_dirs)


def add_to_user_path(directory):
    """Add a directory to the current user's persistent PATH on Windows."""
    import winreg

    key = winreg.OpenKey(
        winreg.HKEY_CURRENT_USER,
        r"Environment",
        0,
        winreg.KEY_READ | winreg.KEY_WRITE,
    )

    try:
        current_path, reg_type = winreg.QueryValueEx(key, "Path")
    except FileNotFoundError:
        current_path = ""
        reg_type = winreg.REG_EXPAND_SZ

    # Check if already in the registry value
    entries = [e.strip() for e in current_path.split(";") if e.strip()]
    norm_dir = os.path.normcase(os.path.normpath(directory))
    if any(os.path.normcase(os.path.normpath(e)) == norm_dir for e in entries):
        return False  # Already present

    # Append and write back
    entries.append(directory)
    new_path = ";".join(entries)
    winreg.SetValueEx(key, "Path", 0, reg_type, new_path)
    winreg.CloseKey(key)

    # Broadcast the change so Explorer and new terminals pick it up
    try:
        import ctypes
        HWND_BROADCAST = 0xFFFF
        WM_SETTINGCHANGE = 0x001A
        SMTO_ABORTIFHUNG = 0x0002
        ctypes.windll.user32.SendMessageTimeoutW(
            HWND_BROADCAST, WM_SETTINGCHANGE, 0, "Environment",
            SMTO_ABORTIFHUNG, 5000, ctypes.byref(ctypes.c_ulong(0)),
        )
    except Exception:
        pass

    return True


def main():
    if sys.platform != "win32":
        print("This script is for Windows only.")
        sys.exit(1)

    scripts_dir = get_scripts_dir()
    print(f"Python Scripts directory: {scripts_dir}")

    if is_on_path(scripts_dir):
        print("Already on PATH — nothing to do.")
        return

    print(f"Adding to user PATH...")
    added = add_to_user_path(scripts_dir)

    if added:
        print(f"Done! '{scripts_dir}' has been added to your user PATH.")
        print("Please open a new terminal for the change to take effect.")
    else:
        print("Directory was already in the registry PATH.")


if __name__ == "__main__":
    main()
