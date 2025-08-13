# Keyboard Shortcut Not Working in Password Fields

## Problem Description

Some users may experience issues where their Maccy keyboard shortcut stops working, particularly in password fields or secure input contexts. This commonly occurs when using shortcuts that produce visible characters, such as `Option+C` which generates the "ç" character.

## Root Cause

macOS blocks keyboard event listeners that output text in secure fields. When a keyboard combination generates a character (like `Option+C` → "ç"), macOS security features prevent third-party applications from intercepting these key events in password fields and other secure input contexts.

## Easy Solution

Choose Different Shortcut: Select a keyboard combination that doesn't produce visible characters (e.g., Cmd+Shift+V)

## Detailed Solution: If you really want to continue using your current kb shortcut

If you want to use a keyboard shortcut that is used by the system (and produces text output), you can use Karabiner-Elements to remap this shortcut to another keyboard shortcut. For example, remapping `Option+C` to `Cmd+Shift+C`.

### Using Karabiner-Elements

1. **Download and Install Karabiner-Elements**

   - Visit: <https://karabiner-elements.pqrs.org/>
   - Download and install the application
   - Grant necessary permissions when prompted

2. **Configure Key Remapping**

   - Open Karabiner-Elements
   - Navigate to "Complex Modifications"
   - Click 'Add your own rule'
   - Paste the following JSON configuration (see example below)
   - Instructions for editing different key combinations: modify the `key_code` and `modifiers` values as needed
   - Give your rule a name (Example: "Remap Option+C to Cmd+Shift+C for clipboard manager")

3. **Example Karabiner Rule**
   This example remaps `Option+C` to `Cmd+Shift+C`:

   ```json
   {
     "description": "Remap option+c to cmd+shift+c for Maccy trigger",
     "manipulators": [
       {
         "from": {
           "key_code": "c",
           "modifiers": {
             "mandatory": ["left_alt"],
             "optional": ["any"]
           }
         },
         "to": [
           {
             "key_code": "c",
             "modifiers": ["left_command", "left_shift"]
           }
         ],
         "type": "basic"
       }
     ]
   }
   ```

4. **Update Maccy Settings**
   - Open Maccy preferences
   - Set the keyboard shortcut to match your Karabiner remapping (in this example: `Cmd+Shift+C`)
   - Test the shortcut in various contexts, including password fields

## Alternative Solutions

- **Choose Different Shortcut**: Select a keyboard combination that doesn't produce visible characters (e.g., `Cmd+Shift+V`)
- **System Keyboard Settings**: Modify system keyboard shortcuts that might conflict with your desired combination

## Verification

After implementing the solution:

1. Test the shortcut in regular text fields
2. Test the shortcut in password fields
3. Test the shortcut in secure applications (banking apps, password managers)
4. Verify Maccy responds consistently across all contexts

This approach allows you to continue using your preferred key combination while ensuring compatibility with macOS security features.
