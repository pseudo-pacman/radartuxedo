## This Script Enables the "Ultimate Performance" Power Plan in Windows 11 when it is unavailablle in the GUI. 

# Enable Ultimate Performance Mode (if not already enabled)
powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61

# Set Ultimate Performance as active power plan
powercfg -setactive e9a42b02-d5df-448d-aa00-03f14749eb61

# Verify the change
powercfg /getactivescheme
