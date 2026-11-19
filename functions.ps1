# oh-my-posh init pwsh | Invoke-Expression
Invoke-Expression (&starship init powershell)

function Add-Alias {
  [CmdletBinding()]
  [OutputType([PSCustomObject])]
  param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$AliasName,

    [Parameter(Mandatory, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [string]$Command,

    [switch]$Force
  )

  $varName = "pro_$AliasName"

  # 1. Create the variable holding the command/path.
  Set-Variable -Name $varName -Value $Command -Scope Global -Force

  # 2. Create the alias from the variable's value (aliases can't point at variables).
  $target = Get-Variable -Name $varName -Scope Global -ValueOnly
  $aliasCreated = $false

  if ($Force -or -not (Get-Command $AliasName -ErrorAction SilentlyContinue)) {
    Set-Alias -Name $AliasName -Value $target -Scope Global -Force
    $aliasCreated = $true
  }
  else {
    Write-Warning "A command named '$AliasName' already exists; alias skipped. Use -Force to overwrite."
  }

  # 3. Report what was created.
  [PSCustomObject]@{
    Variable     = "`$$varName"
    Alias        = $AliasName
    Target       = $target
    AliasCreated = $aliasCreated
  }
}

$pro_ffmpeg = & 'C:\mega\IDEs\powershell\ffmpeg\ffmpeg-find.ps1'
$pro_ffprobe = & 'C:\mega\IDEs\powershell\ffmpeg\ffmpeg-find.ps1' -Executable 'ffprobe'

@(
  Add-Alias 'ffmpeg' $pro_ffmpeg
  Add-Alias 'ffprobe' $pro_ffprobe
  Add-Alias 'sqlite3' 'C:\mega\program-files\sqlite-tools\sqlite3.exe'
  Add-Alias 'es' 'C:\mega\program-files\Everything\es.exe'
  Add-Alias 'mpv' 'C:\Program Files\MPV Player\mpv.com' -Force
  Add-Alias 'mpv-exe' 'C:\Program Files\MPV Player\mpv.exe'
) | Format-Table -AutoSize



# Add-Type -AssemblyName PresentationCore, PresentationFramework
# Add-Type -AssemblyName System.Windows.Forms

#  MARK: WPF guis

function Show-WpfFormOnMonitor {
  param (
    [Parameter(Mandatory = $true)]
    [System.Windows.Window]$WpfForm,

    [Parameter(Mandatory = $true)]
    [int]$MonitorIndex,

    $FullWidth = $false
  )

  if (-not ('GalleryDl.MonitorDpi' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;

namespace GalleryDl {
  public static class MonitorDpi {
    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromPoint(Point point, uint flags);

    [DllImport("shcore.dll")]
    private static extern int GetDpiForMonitor(
      IntPtr monitor,
      int dpiType,
      out uint dpiX,
      out uint dpiY);

    [StructLayout(LayoutKind.Sequential)]
    private struct Point {
      public int X;
      public int Y;

      public Point(int x, int y) {
        X = x;
        Y = y;
      }
    }

    public static uint GetDpi(int x, int y) {
      var monitor = MonitorFromPoint(new Point(x, y), 2);
      uint dpiX;
      uint dpiY;
      var result = GetDpiForMonitor(monitor, 0, out dpiX, out dpiY);
      if (result != 0) {
        throw new InvalidOperationException(
          "Unable to determine the DPI for the selected monitor. HRESULT: " + result);
      }

      return dpiX;
    }
  }
}
'@
  }

  $screens = [System.Windows.Forms.Screen]::AllScreens
  if ($MonitorIndex -lt 0 -or $MonitorIndex -ge $screens.Count) {
    throw "Monitor index $MonitorIndex is outside the available monitor range (0-$($screens.Count - 1))."
  }

  $targetScreen = $screens[$MonitorIndex]
  $screenBounds = $targetScreen.WorkingArea
  $scale = [GalleryDl.MonitorDpi]::GetDpi($screenBounds.X, $screenBounds.Y) / 96
  $workingWidth = $screenBounds.Width / $scale
  $workingHeight = $screenBounds.Height / $scale
  $workingLeft = $screenBounds.X / $scale
  $workingTop = $screenBounds.Y / $scale
  $formWidth = $WpfForm.Width
  $formHeight = $WpfForm.Height

  if ( $FullWidth ) {
    $WpfForm.Width = $workingWidth
    $left = $workingLeft
  }
  else {
    $left = $workingLeft + (($workingWidth - $formWidth) / 2)
  }

  $top = $workingTop + (($workingHeight - $formHeight) / 2)

  # Set the form's position
  $WpfForm.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
  $WpfForm.Left = $left
  $WpfForm.Top = $top

  # Show the form
  $WpfForm.ShowDialog()
}
function GuiFromXaml {
  param ( $XamlTextOrXamlFile )

  if ( Test-Path $XamlTextOrXamlFile ) {
    $XamlContent = Get-Content -Path $XamlTextOrXamlFile -Raw
  }
  else {
    $XamlContent = $XamlTextOrXamlFile
  }

  # Add the required assemblies
  Add-Type -AssemblyName PresentationFramework
  Add-Type -AssemblyName PresentationCore
  Add-Type -AssemblyName WindowsBase

  # Clean up XAML content - doing each replacement separately
  $XamlContent = $XamlContent -replace 'x:Class="[^"]*"', ''
  $XamlContent = $XamlContent -replace 'mc:Ignorable="d"', ''
  $XamlContent = $XamlContent -replace 'x:N', 'N'
  $XamlContent = $XamlContent -replace 'xmlns:mc="[^"]*"', ''
  $XamlContent = $XamlContent -replace 'xmlns:d="[^"]*"', ''
  $XamlContent = $XamlContent -replace 'xmlns:x="[^"]*"', ''
  $XamlContent = $XamlContent -replace 'SelectionChanged="[^"]*"', ''
  $XamlContent = $XamlContent -replace 'Click="[^"]*"', ''

  # Ensure there's only one xmlns declaration
  if ($XamlContent -notmatch 'xmlns=') {
    $XamlContent = $XamlContent -replace '<Window', '<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"'
  }

  [XML]$XAML = $XamlContent

  $reader = New-Object System.Xml.XmlNodeReader $XAML
  try {
    $psForm = [Windows.Markup.XamlReader]::Load($reader)
  }
  catch {
    Write-Host "Error loading XAML: $_"
    throw
  }

  # Create variables for named controls
  $XAML.SelectNodes('//*[@Name]') | ForEach-Object {
    try {
      $name = "wpf_$($_.Name)"
      $value = $psForm.FindName($_.Name)
      Set-Variable -Name $name -Value $value -Scope Global
      Write-Verbose "Created variable '$name'"
    }
    catch {
      Write-Warning "Failed to process element '$($_.Name)': $_"
    }
  }

  return $psForm
}

# MARK: String functions

function Get-UniqueId {
  <#
    .SYNOPSIS
    Generates a unique alphanumeric identifier (UID) of a specified length.

    .DESCRIPTION
    This function generates a random alphanumeric string of a specified length.
    Optionally, a prefix can be added to the ID.

    .PARAMETER Length
    The length of the unique alphanumeric ID. Default is 10.

    .PARAMETER Prefix
    An optional prefix to add to the beginning of the ID.

    .EXAMPLE
    Get-UniqueId
    Outputs: "a7B9c3E8dF" (Default length: 10)

    .EXAMPLE
    Get-UniqueId -Length 15 -Prefix "App"
    Outputs: "App-a7B9c3E8dF2GhY"

    .NOTES
    Author: Your Name
    Date: 24-Nov-2024
    #>

  param (
    [int]$Length = 10,
    [string]$Prefix = '',
    $EsPath
  )

  if ($Length -le 0) {
    throw 'Length must be a positive integer.'
  }

  $characters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
  $randomId = -join ((1..$Length) | ForEach-Object { $characters[(Get-Random -Minimum 0 -Maximum $characters.Length)] })

  if ( $EsPath ) {
    $existingIds = & $EsPath $randomId -count 1
    if ($existingIds) {
      return Get-UniqueId -Length $Length -Prefix $Prefix -EsPath $EsPath
    }
  }

  # Add prefix if provided
  if ($Prefix -ne '') {
    return "$Prefix$randomId"
  }
  else {
    return $randomId
  }
}

function ConvertTo-Seconds {
  param (
    [string]$Time # input time in the format of HH:MM:SS
  )
  $null = $Time -match '^(\d+?):(\d+?):(\d+?)($|-)'
  [int]$HoursInSeconds = [int]$Matches[1] * 60 * 60
  [int]$MinutesInSeconds = [int]$Matches[2] * 60
  [int]$SecondsInSeconds = [int]$Matches[3]
  [int]$TotalSeconds = $HoursInSeconds + $MinutesInSeconds + $SecondsInSeconds
  return $TotalSeconds
}

function Get-UniqueTags {
  param (
    [string[]]$FilePaths
  )

  # Create an empty array to store all tags
  $allTags = @()

  foreach ($filePath in $FilePaths) {
    # Use regex to find all tags in the format [tag-name]
    $TagsMatches = [regex]::Matches($filePath, '\[\w+\]')

    foreach ($match in $TagsMatches) {
      # Add the tag to the array
      $allTags += $match.Value
    }
  }

  # Get unique tags and join them into a single string
  $uniqueTags = $allTags | Sort-Object -Unique

  return ($uniqueTags -join '')
}

function Get-LongestCommonSubstring {
  param (
    [string[]]$arr
  )

  $commonSubstrings = $arr | ForEach-Object {
    $substrings = @()
    for ($s = 0; $s -lt $_.Length; $s++) {
      for ($l = 1; $l -le ($_.Length - $s); $l++) {
        $substrings += $_.Substring($s, $l)
      }
    }
    $substrings | ForEach-Object { $_.ToLower() } | Select-Object -Unique
  }

  $commonSubstrings | Group-Object | Where-Object { $_.Count -eq $arr.Length } |
    Sort-Object { $_.Name.Length } -Descending |
      Select-Object -ExpandProperty Name -First 1
}

function cleanString {
  param( [string] $string )
  $out = $string -replace ( 'https\:\/\/t\.co\/', ', ' )
  $out = $out -replace ( '&amp;' , '&' )
  $out = $out -replace ( '/' , ' ' )
  $out = $out -replace ( '\n'    , ' ' )
  $out = $out -replace ( '\s{2,}', ' ' )
  return $out
}

#  MARK: Cli/Gui 

function Countdown {
  param(
    [parameter(Mandatory)]
    [int]$TotalSeconds,
    [String]$Message = 'Countdown in progress...'
  )

  for ($SecondsLeft = $TotalSeconds; $SecondsLeft -ge 0; $SecondsLeft--) {
    $PercentComplete = ($SecondsLeft / $TotalSeconds) * 100
    
    Write-Progress -Activity "$Message" `
      -Status "$SecondsLeft seconds remaining" `
      -PercentComplete $PercentComplete
                   
    Start-Sleep -Seconds 1
  }

}

function show-notification {
  param (
    $IconPath = ( Get-Process -Id $PID ).Path,
    $NotificationType = 'Info',
    $BodyText = '',
    $TitleText = '',
    $Duration = 5000 )
    
  $global:Notification = New-Object -TypeName System.Windows.Forms.NotifyIcon -Property @{
    Icon            = [System.Drawing.Icon]::ExtractAssociatedIcon( $IconPath )
    BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::$NotificationType
    BalloonTipText  = $BodyText
    BalloonTipTitle = $TitleText
    Visible         = $true
  }
  $Notification.ShowBalloonTip( $Duration )
}

function MessageBox {
  param ( $body, $title = '', $buttons = 'Ok', $type = 'None' )
  return [System.Windows.MessageBox]::Show( $body, $title, $buttons, $type )
}

function animation {
  param ( $frames, $loops = -1, $speed = 250 )

  # $loops = -1 makes this run infinitely 

  $i = 0
  do {

    foreach ($frame in $frames) {
      Write-Host -NoNewline "`r$frame  "
      Start-Sleep -Milliseconds $speed
    }

    $i++
      
  } until ( $i -eq $loops )

}

#  MARK: Terminal

function restart {
  wt -w 0 new-tab
  exit
}

function activate {
  $null = (New-Object -ComObject WScript.Shell).AppActivate((Get-Process -Id $pid).MainWindowTitle)
}

function exitAndCloseTerminal { 
  if ( $Debug ) {
    exit
  } 
  else {
    [Environment]::Exit(0)
  }
}

function RunAsAdmin {
  
  # Get the current script path
  $scriptPath = $MyInvocation.PSCommandPath
    
  # Check if the script is running as admin
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
  # If not admin, restart script with admin privileges
  if (-not $isAdmin) {
    Write-Host 'Requesting administrative privileges...'
    Start-Process pwsh -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $args"
    exit
  }
    
  Write-Host '🕴️ Script is running with administrative privileges'
  return $isAdmin
}

#  MARK: Rest

function New-Junction {
  param (
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$LinkPath
  )

  RunAsAdmin

  # Check if the source file exists
  if (-not (Test-Path -Path $SourcePath)) {
    throw "Source file '$SourcePath' does not exist."
  }

  # Check if the link path already exists
  if (Test-Path -Path $LinkPath) {
    throw "Link path '$LinkPath' already exists."
  }

  # Remove existing links/directories if they exist
  if (Test-Path $NewDir) {
    Add-Type -AssemblyName Microsoft.VisualBasic; 
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($NewDir, 'OnlyErrorDialogs', 'SendToRecycleBin')
  }

  $result = New-Item -ItemType Junction -Path $LinkPath -Target $SourcePath -ErrorAction Stop
  return $result
}

function ListJoin {
  param ( $ListItems )
  
  $NewList = @()
  
  foreach ($currentItemName in $ListItems) {
  
    if ( $currentItemName ) {
      $NewList += $currentItemName 
    }

  }
  
  return $NewList

}

function beep {
  [console]::beep(1500, 50)
  [console]::beep(2000, 50)
  [console]::beep(2500, 50)
}
function anyKey {
  Write-Host -NoNewline 'Press any key to continue...'
  $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

function checkFile {
  param ( [string] $originalFilename, [string] $options )
  
  if ( -not ( Test-Path -LiteralPath $originalFilename ) ) { return $originalFilename }
    
  $ParentPath = Split-Path -Path $originalFilename -Parent
  $LeafBase = Split-Path -Path $originalFilename -LeafBase
  $Extension = Split-Path -Path $originalFilename -Extension
  $pattern = '_(\d+)\s*$'
  if ( $LeafBase -match $pattern ) {
    $Number = [int]$Matches[1]
    $Number++
    $NewLeafBase = $LeafBase -replace $pattern, "_$Number"
    $NewFNWithPath = $ParentPath ? "$ParentPath\$NewLeafBase$Extension" : "$NewLeafBase$Extension"
    return checkFile $NewFNWithPath
  }

  return checkFile "$($ParentPath ? "$ParentPath\" : '' )$($LeafBase)_1$Extension"

}

function Show-JsonTreeView {

  param (
    [Parameter(Mandatory)]
    $Json
  )

  function Show-jsonTreeView_psf {

    #----------------------------------------------
    #region Import the Assemblies
    #----------------------------------------------
    [void][reflection.assembly]::Load('System.Windows.Forms, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089')
    [void][reflection.assembly]::Load('System.Drawing, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a')
    #endregion Import Assemblies

    #----------------------------------------------
    #region Generated Form Objects
    #----------------------------------------------
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $formJSONTreeView = New-Object 'System.Windows.Forms.Form'
    $treeview1 = New-Object 'System.Windows.Forms.TreeView'
    $InitialFormWindowState = New-Object 'System.Windows.Forms.FormWindowState'
    #endregion Generated Form Objects

    #----------------------------------------------
    # User Generated Script
    #----------------------------------------------

    function Add-JsonToTreeview {
  
      ########################################################################################
      #                                                                                      #
      #    The MIT License                                                                   #
      #                                                                                      #
      #    Copyright (c) 2019 Matt Oestreich. http://mattoestreich.com                       #
      #                                                                                      #
      #    Permission is hereby granted, free of charge, to any person obtaining a copy      #
      #    of this software and associated documentation files (the "Software"), to deal     #
      #    in the Software without restriction, including without limitation the rights      #
      #    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell         #
      #    copies of the Software, and to permit persons to whom the Software is             #
      #    furnished to do so, subject to the following conditions:                          #
      #                                                                                      #
      #    The above copyright notice, accreditation to Matt Oestreich, and this permission  #
      #    notice shall be included in all copies or substantial portions of the Software.   #
      #                                                                                      #
      #    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR        #
      #    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,          #
      #    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE       #
      #    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER            #
      #    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,     #
      #    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN         #
      #    THE SOFTWARE.                                                                     #
      #                                                                                      #
      ########################################################################################
  
      <#
                  .SYNOPSIS
                  Add JSON to TreeView
  
                  .DESCRIPTION
                  Add JSON to TreeView (System.Windows.Forms.TreeView) Component
  
                  .PARAMETER Json
                  JSON data (`-Json` can be a `[String]` or converted JSON string (aka `[PsCustomObject]`) converted using `ConvertFrom-Json`). See examples for more details.
  
                  .PARAMETER TreeView
                  The TreeView (System.Windows.Forms.TreeView) that you want to add JSON to
  
                  .PARAMETER ParentNode
                  This is here for recursion - you will most likely not need to use this Parameter
                  9.99 times out of 10.00 you wil not need to use this Parameter
  
                  .EXAMPLE
                  PS C:\> $SomeTreeView = [System.Windows.Forms.TreeView]::new()
                  PS C:\> $myJsonString = '{ "Root": [{ "Child1": "Value1" }, { "Child2": "Value2" }, { "Child3": "Value3" }] }'
                  PS C:\> $myJsonConverted = $myJsonString | ConvertFrom-Json
                  PS C:\> Add-JsonToTreeview -Json $myJsonConverted -TreeView $SomeTreeView

                  .EXAMPLE
                  PS C:\> $SomeTreeView = [System.Windows.Forms.TreeView]::new()
                  PS C:\> $myJsonString = '{ "Root": [{ "Child1": "Value1" }, { "Child2": "Value2" }, { "Child3": "Value3" }] }'
                  PS C:\> Add-JsonToTreeview -Json $myJsonString -TreeView $SomeTreeView
  
                  .NOTES
                  Matt Oestreich | http://mattoestreich.com | https://github.com/oze4
          #>
  
      param (
        [Parameter(Mandatory)]
        $Json,
    
        [Parameter(Mandatory)]
        [Windows.Forms.TreeView]$TreeView,
    
        [Parameter()]
        [Windows.Forms.TreeNode]$ParentNode
      )
  
      begin {
        function New-TreeViewNode {
          param (
            [Parameter(Mandatory)]
            [string]$Value
          )
          $NewNode = [Windows.Forms.TreeNode]::new($Value)
          $NewNode.Name = $Value
          return $NewNode
        }
    
        function Add-ObjectToTreeView {
          param (
            [Parameter(Mandatory)]
            [System.Object[]]$Object,
        
            [Parameter()]
            [Windows.Forms.TreeNode]$AddToNode,
        
            [Parameter(Mandatory)]
            [Windows.Forms.TreeView]$TargetTreeView
          )
          $counter = 1
          foreach ($objectProp in $Object) {
            if ((($objectProp | Get-Member -Type NoteProperty).Count) -gt 1) {
              $objectProp = "{ `"$($counter)`": $($objectProp | ConvertTo-Json) }" | ConvertFrom-Json
              $counter++
            }
            Add-JsonToTreeview -Json $objectProp -ParentNode $AddToNode -TreeView $TargetTreeView
          }
        }
    
        function Find-ParentNode {
          param (
            [Parameter(Mandatory)]
            [Windows.Forms.TreeView]$TreeView,
        
            [Parameter(Mandatory)]
            [AllowNull()]
            [Windows.Forms.TreeNode]$TreeNode
          )
          $parent = $TreeView
          if ($TreeNode) {
            $parent = $TreeNode
          }
          return $parent
        }
      }
      process {
        switch ($Json.GetType().Name) {
          'PsCustomObject' {
            foreach ($jsonProperty in $Json.PsObject.Properties) {
              $node = New-TreeViewNode -Value $jsonProperty.Name
              (Find-ParentNode -TreeView $TreeView -TreeNode $ParentNode).Nodes.Add($node)
              if ($jsonProperty.GetType().Name -eq 'Object[]') {
                Add-ObjectToTreeView -Object $jsonProperty -AddToNode $node -TargetTreeView $TreeView
              }
              else {
                Add-JsonToTreeview -Json $jsonProperty.Value -ParentNode $node -TreeView $TreeView
              }
            }
          }
      
          'Object[]' {
            Add-ObjectToTreeView -Object $Json -AddToNode $ParentNode -TargetTreeView $TreeView
          }
      
          'String' {
            try {
              Add-JsonToTreeview -Json ($Json | ConvertFrom-Json) -ParentNode $ParentNode -TreeView $TreeView
            }
            catch {
              (Find-ParentNode -TreeView $TreeView -TreeNode $ParentNode).Nodes.Add((New-TreeViewNode -Value $Json))
            }
          }
        }
    
        if ($Json -is [ValueType]) {
          try {
            (Find-ParentNode -TreeView $TreeView -TreeNode $ParentNode).Nodes.Add((New-TreeViewNode -Value $Json.ToString()))
          }
          catch {
          }
        }
      }
    }



    $formJSONTreeView_Load = {
      Add-JsonToTreeview -Json $Json -TreeView $treeview1
    }

    # --End User Generated Script--
    #----------------------------------------------
    #region Generated Events
    #----------------------------------------------

    $Form_StateCorrection_Load =
    {
      #Correct the initial state of the form to prevent the .Net maximized form issue
      $formJSONTreeView.WindowState = $InitialFormWindowState
    }

    $Form_Cleanup_FormClosed =
    {
      #Remove all event handlers from the controls
      try {
        $formJSONTreeView.remove_Load($formJSONTreeView_Load)
        $formJSONTreeView.remove_Load($Form_StateCorrection_Load)
        $formJSONTreeView.remove_FormClosed($Form_Cleanup_FormClosed)
      }
      catch { Out-Null <# Prevent PSScriptAnalyzer warning #> }
    }
    #endregion Generated Events

    #----------------------------------------------
    #region Generated Form Code
    #----------------------------------------------
    $formJSONTreeView.SuspendLayout()
    #
    # formJSONTreeView
    #
    $formJSONTreeView.Controls.Add($treeview1)
    $formJSONTreeView.AutoScaleDimensions = '6, 13'
    $formJSONTreeView.AutoScaleMode = 'Font'
    $formJSONTreeView.ClientSize = '440, 606'
    $formJSONTreeView.MaximizeBox = $False
    $formJSONTreeView.MinimizeBox = $False
    $formJSONTreeView.Name = 'formJSONTreeView'
    $formJSONTreeView.Text = 'JSON TreeView'
    $formJSONTreeView.add_Load($formJSONTreeView_Load)
    #
    # treeview1
    #
    $treeview1.Location = '12, 12'
    $treeview1.Name = 'treeview1'
    $treeview1.Size = '416, 582'
    $treeview1.TabIndex = 0
    $formJSONTreeView.ResumeLayout()
    #endregion Generated Form Code

    #----------------------------------------------

    #Save the initial state of the form
    $InitialFormWindowState = $formJSONTreeView.WindowState
    #Init the OnLoad event to correct the initial state of the form
    $formJSONTreeView.add_Load($Form_StateCorrection_Load)
    #Clean up the control events
    $formJSONTreeView.add_FormClosed($Form_Cleanup_FormClosed)
    #Show the Form
    return $formJSONTreeView.ShowDialog()

  } #End Function

  #Call the form
  Show-jsonTreeView_psf | Out-Null
}

#  MARK: System

function Get-DiskFreeSpace {
  <#
    .SYNOPSIS
    Lists the free space of each logical disk in GB.

    .DESCRIPTION
    Queries Win32_LogicalDisk through CIM and returns one object per drive
    with its drive letter, volume label, and free space in gigabytes
    (rounded to 2 decimals).

    .OUTPUTS
    [PSCustomObject] with the properties:
      - DeviceID       [string] Drive letter, e.g. "C:"
      - VolumeName     [string] Volume label (may be empty)
      - 'FreeSpace (GB)' [double] Free space in GB

    .EXAMPLE
    Get-DiskFreeSpace

    Shows free space for all logical disks.

    .EXAMPLE
    Get-DiskFreeSpace | Where-Object DeviceID -eq 'C:'

    Shows free space for the C: drive only.

    .EXAMPLE
    Get-DiskFreeSpace | Sort-Object 'FreeSpace (GB)' -Descending

    Sorts drives by most free space first.
    #>
  [CmdletBinding()]
  [OutputType([PSCustomObject])]
  param()

  Get-CimInstance -ClassName Win32_LogicalDisk |
    Select-Object -Property DeviceID, VolumeName, @{
      Label      = 'FreeSpace (GB)'
      Expression = { [Math]::Round($_.FreeSpace / 1GB, 2) }
    }
}

function Get-LastWindowCli {
  Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
}
'@

  $hwnd = [Win32]::GetForegroundWindow()
  $procId = 0
  [Win32]::GetWindowThreadProcessId($hwnd, [ref]$procId) | Out-Null

  $proc = Get-CimInstance Win32_Process -Filter "ProcessId = $procId"
  $cmdLine = $proc.CommandLine
  $exeName = $proc.Name

  Write-Output "Process: $exeName"
  Write-Output "Command line: $cmdLine"

  return $cmdLine

  if ($cmdLine -match '--profile-directory="?([^"]+)"?') {
    $profileDir = $matches[1]
  }
  else {
    $profileDir = 'Default'
  }
  Write-Output "Profile directory: $profileDir"
}

#  MARK: GIT

function Invoke-git-sync {
  Write-Host 'Syncing with remote repository...' -ForegroundColor DarkGreen
  Write-Host 'git pull ...' -ForegroundColor DarkGreen
  git pull --no-rebase
  if ($LASTEXITCODE -eq 0) {
    Write-Host 'Pull successful. Pushing changes...' -ForegroundColor DarkGreen
    git push
  }
  else {
    Write-Host 'Pull failed — resolve conflicts before pushing.' -ForegroundColor Red
  }
}

#  MARK: File system operations

<#
.SYNOPSIS
Gets the other files in the same folder whose names start with a file's base name.

.DESCRIPTION
Given the path to a file, returns every other file in that file's directory
whose name is the input's base name (file name without the final extension)
followed by a dot and anything else. This finds companions such as
'name.srt', 'name.en.srt' and 'name.mkv.playtime' for 'name.mkv'.
The input file itself is excluded and does not need to exist. Matching is
case-insensitive and uses plain string comparison, so wildcard characters
such as [ ] in names are handled safely.

.PARAMETER Path
Full or relative path to the reference file, e.g. 'C:\media\tv\carrie\carrie.s01e03.mkv'.
Accepts pipeline input, including objects with a FullName or PSPath property
(such as output from Get-ChildItem).

.EXAMPLE
Get-SiblingFile 'C:\media\tv\carrie\carrie.s01e03.1080p.web.h264-cakes[EZTVx.to].mkv'

Returns carrie.s01e03.1080p.web.h264-cakes[EZTVx.to].mkv.playtime if it exists.

.EXAMPLE
Get-ChildItem 'C:\media\tv\carrie' -Filter *.mkv | Get-SiblingFile | Select-Object -ExpandProperty FullName

Lists all companion files for every .mkv in the folder.

.INPUTS
System.String. A file path.

.OUTPUTS
System.IO.FileInfo. One object per matching sibling file.

.NOTES
A file such as 'name.2.mkv' also matches 'name.mkv', because it starts with 'name.'.
#>
function Get-SiblingFiles {
  [CmdletBinding()]
  [OutputType([System.IO.FileInfo])]
  [Alias('sdf')]
  param(
    [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [Alias('FullName', 'PSPath')]
    [ValidateNotNullOrEmpty()]
    [string]$Path
  )

  process {
    $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $directory = [System.IO.Path]::GetDirectoryName($fullPath)
    $prefix = [System.IO.Path]::GetFileNameWithoutExtension($fullPath) + '.'

    Get-ChildItem -LiteralPath $directory -File |
      Where-Object {
        $_.Name.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) -and
        $_.FullName -ine $fullPath
      }
  }
}

function Move-ToRecycleBin {
  param ([Parameter(Mandatory = $true, ValueFromPipeline = $true)][string]$Path)
  $FullPath = Resolve-Path $Path
  Add-Type -AssemblyName Microsoft.VisualBasic
  if (Test-Path $FullPath -PathType Container) {
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($FullPath, 'OnlyErrorDialogs', 'SendToRecycleBin')
  }
  else {
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($FullPath, 'OnlyErrorDialogs', 'SendToRecycleBin')
  }
}
