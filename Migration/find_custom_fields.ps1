# Find custom fields using witadmin and grep
# Basic logic: find all fields and exclude Fields which start with Microsoft or System

# Prerequisites:
# Powershell, VS 2022, gnu tool: grep
&"C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\witadmin.exe" listfields /collection:https://dev.azure.com/<placeholder> | grep "Field:" | grep -v "System" | grep -v "Microsoft"
