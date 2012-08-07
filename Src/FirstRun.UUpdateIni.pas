{
 * FirstRun.UUpdateIni.pas
 *
 * Pascal script for use in [Code] Section of CodeSnip's Install.iss.
 *
 * Creates per-user and application-wide ini files in correct data folders. Can
 * also create the ini files from the information stored in the single ini file
 * used in versions of CodeSnip prior to version 1.9.
 *
 * $Rev$
 * $Date$
 *
 * ***** BEGIN LICENSE BLOCK *****
 *
 * Version: MPL 1.1
 *
 * The contents of this file are subject to the Mozilla Public License Version
 * 1.1 (the "License"); you may not use this file except in compliance with the
 * License. You may obtain a copy of the License at http://www.mozilla.org/MPL/
 *
 * Software distributed under the License is distributed on an "AS IS" basis,
 * WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for
 * the specific language governing rights and limitations under the License.
 *
 * The Original Code is FirstRun.UUpdateIni.pas, formerly UpdateIni.ps.
 *
 * The Initial Developer of the Original Code is Peter Johnson
 * (http://www.delphidabbler.com/).
 *
 * Portions created by the Initial Developer are Copyright (C) 2007-2012 Peter
 * Johnson. All Rights Reserved.
 *
 * Contributors:
 *    NONE
 *
 * ***** END LICENSE BLOCK *****
}

unit FirstRun.UUpdateIni;

interface

// Create a new empty UTF-16LE encoded config file. Used to ensure the config
// file writing routines write in Unicode. This works because built in Inno
// Setup ini functions call Windows API WritePrivateProfileString which only
// writes Unicode if the file it is writing to is detected as Unicode. If not it
// writes ANSI text.
procedure CreateUnicodeConfigFile(FileName: string);

// Updates config file copied from old stye (pre CodeSnip v1.9) file
procedure UpdateOldStyleIniFile;

// Copies config files of a previous installation to new installation, updating
// to Unicode format if necessary.
procedure CopyConfigFiles(InstallID: Integer);

// Deletes any highlighter preferences from new installation's user config file.
procedure DeleteHighligherPrefs;

// Gets version number of new installation's user config file.
function UserConfigFileVer: Integer;

// Gets version number of program from user config file. Returns empty string if
// no program version information is present
function ConfigFileProgramVer: string;

// Adds Prefs:CodeGen section along with default data to new installation's user
// config file.
procedure CreateDefaultCodeGenEntries;

// Deletes proxy password entry from new installation's user config file.
procedure DeleteProxyPassword;

// Updates both common and user config files with correct version information.
// This records both config file versions and (common config file only) version
// number of program being installed.
procedure StampConfigFiles;

// Checks if program version from config file is same as current program
// version.
function IsCurrentProgramVer: Boolean;

// Checks if current user's config file has a proxy password.
function HasProxyPassword: Boolean;

// Deletes config file from given previous installation
procedure DeleteUserCfgFile(InstallID: Integer);

implementation

uses
  SysUtils, Types, Classes, Windows,
  FirstRun.UDataLocations, UAppInfo, UIOUtils;

// #################### FROM INNO SETUP SOURCE

{ TODO: If any of the Inno setup source is used then move it into it own unit
        that meets with Inno setup license requirements }

function GetIniString(const Section, Key: String; Default: String;
  const Filename: String): String;
var
  BufSize, Len: Integer;
begin
  { On Windows 9x, Get*ProfileString can modify the lpDefault parameter, so
  make sure it's unique and not read-only }
  UniqueString(Default);
  BufSize := 256;
  while True do begin
    SetString(Result, nil, BufSize);
    if Filename <> '' then
      Len := GetPrivateProfileString(PChar(Section), PChar(Key), PChar(Default),
        @Result[1], BufSize, PChar(Filename))
    else
      Len := GetProfileString(PChar(Section), PChar(Key), PChar(Default),
        @Result[1], BufSize);
    { Work around bug present on Windows NT/2000 (not 95): When lpDefault is
    too long to fit in the buffer, nSize is returned (null terminator counted)
    instead of nSize-1 (what it's supposed to return). So don't trust the
    returned length; calculate it ourself.
    Note: This also ensures the string can never include embedded nulls. }
    if Len <> 0 then
      Len := StrLen(PChar(Result));
    { Break if the string fits, or if it's apparently 64 KB or longer.
    No point in increasing buffer size past 64 KB because the length returned by
    Windows 2000 seems to be mod 65536. And Windows 95 returns 0 on values
    longer than ~32 KB. Note: The docs say the function returns "nSize minus
    one" if the buffer is too small, but I'm willing to bet it can be "minus
    two" if the last character is double-byte. Let's just be extremely paranoid
    and check for BufSize-8. }
    if (Len < BufSize-8) or (BufSize >= 65536) then begin
      SetLength(Result, Len);
      Break;
    end;
    { Otherwise double the buffer size and try again }
    BufSize := BufSize * 2;
  end;
end;

function GetIniInt(const Section, Key: String;
  const Default, Min, Max: Longint; const Filename: String): Longint;
{ Reads a Longint from an INI file. If the Longint read is not between Min/Max
then it returns Default. If Min=Max then Min/Max are ignored }
var
  S: String;
  E: Integer;
begin
  S := GetIniString(Section, Key, '', Filename);
  if S = '' then
    Result := Default
  else begin
    Val(S, Result, E);
    if (E <> 0) or ((Min <> Max) and ((Result < Min) or (Result > Max))) then
      Result := Default;
  end;
end;

function SetIniString(const Section, Key, Value, Filename: String): Boolean;
begin
  if Filename <> '' then
    Result := WritePrivateProfileString(PChar(Section), PChar(Key),
      PChar(Value), PChar(Filename))
  else
    Result := WriteProfileString(PChar(Section), PChar(Key),
      PChar(Value));
end;

function SetIniInt(const Section, Key: String; const Value: Longint;
  const Filename: String): Boolean;
begin
  Result := SetIniString(Section, Key, IntToStr(Value), Filename);
end;

procedure DeleteIniSection(const Section, Filename: String);
begin
  if Filename <> '' then
    WritePrivateProfileString(PChar(Section), nil, nil,
      PChar(Filename))
  else
    WriteProfileString(PChar(Section), nil, nil);
end;

// ################### END

// Reads an ANSI config file, converts content to Unicode and writes that to a
// UTF-16LE encoded Unicode config file with BOM. Does nothing if old and new
// file names are the same.
// *** Requires Unicode Inno Setup. ***
procedure CopyAnsiToUnicodeConfigFile(OldFileName, NewFileName: string);
var
  Lines: TStringDynArray;  // lines of text read from ANSI .ini file
begin
  if CompareText(OldFileName, NewFileName) = 0 then
    Exit;
  // reads an ANSI file and converts contents to Unicode, using system default
  // encoding
  Lines := TFileIO.ReadAllLines(OldFileName, TEncoding.Default);
  // writes string array to UTF-16LE file
  ForceDirectories(ExtractFileDir(NewFileName));
  TFileIO.WriteAllLines(NewFileName, Lines, TEncoding.Unicode, True);
end;

// Makes a copy of a Unicode config file with a different name. Does nothing if
// old and new file names are the same.
procedure CopyUnicodeConfigFiles(OldFileName, NewFileName: string);
begin
  if CompareText(OldFileName, NewFileName) = 0 then
    Exit;
  ForceDirectories(ExtractFileDir(NewFileName));
  TFileIO.CopyFile(OldFileName, NewFileName);
end;

// Checks if a config file is ANSI. If False is returned the file is assumed to
// be Unicode.
function IsAnsiConfigFile(InstallID: Integer): Boolean;
begin
  Result := InstallID <= piV3;
end;

// Gets version number of new installation's user config file.
function UserConfigFileVer: Integer;
begin
  Result := GetIniInt('IniFile', 'Version', 1, 0, 0, gCurrentUserConfigFile);
end;

// Gets version number of program from user config file. Returns empty string if
// no program version information is present
function ConfigFileProgramVer: string;
begin
  Result := GetIniString(
    'IniFile', 'ProgramVersion', '', gCurrentUserConfigFile
  );
end;

// Create a new empty UTF-16LE encoded config file. Used to ensure the config
// file writing routines write in Unicode. This works because built in Inno
// Setup ini functions call Windows API WritePrivateProfileString which only
// writes Unicode if the file it is writing to is detected as Unicode. If not it
// writes ANSI text.
procedure CreateUnicodeConfigFile(FileName: string);
begin
  ForceDirectories(ExtractFileDir(FileName));
  TFileIO.WriteAllText(FileName, '', TEncoding.Unicode, True);
end;

// Copies config files of a previous installation to new installation, updating
// to Unicode format if necessary.
procedure CopyConfigFiles(InstallID: Integer);
var
  OldUserConfigFile: string;
begin
  OldUserConfigFile := gUserConfigFiles[InstallID];
  if OldUserConfigFile <> '' then
  begin
    if IsAnsiConfigFile(InstallID) then
      CopyAnsiToUnicodeConfigFile(OldUserConfigFile, gCurrentUserConfigFile)
    else
      CopyUnicodeConfigFiles(OldUserConfigFile, gCurrentUserConfigFile);
  end;
end;

// Updates both common and user config files with correct version information.
// This records both config file versions and (common config file only) version
// number of program being installed.
procedure StampConfigFiles;
begin
  // Config file Meta data: config file version & program version
  if not FileExists(gCurrentUserConfigFile) then
    CreateUnicodeConfigFile(gCurrentUserConfigFile);
  SetIniInt('IniFile', 'Version', 8, gCurrentUserConfigFile);
  SetIniString(
    'IniFile',
    'ProgramVersion',
    TAppInfo.ProgramReleaseVersion,
    gCurrentUserConfigFile
  );
end;

// Checks if program version from config file is same as current program
// version.
function IsCurrentProgramVer: Boolean;
begin
  Result := ConfigFileProgramVer = TAppInfo.ProgramReleaseVersion;
end;

// Deletes any highlighter preferences from new installation's user config file.
procedure DeleteHighligherPrefs;
begin
  DeleteIniSection('Prefs:Hiliter', gCurrentUserConfigFile);
end;

// Updates config file copied from old stye (pre CodeSnip v1.9) file
procedure UpdateOldStyleIniFile;
var
  I: Integer; // loops thru all highlight elements
begin
  // Delete unwanted sections:
  // - Application section: now in common config file
  // - Source code output format: format lost when updating from CodeSnip pre
  //   1.7 since section was SourceOutput, but format preserved from v1.7 since
  //   current Prefs:SourceCode section used
  // - Highlighting style is deliberately lost since CodeSnip v3 & v4 have
  //   different default style and main display uses that style, therefore
  //   section's HiliteOutput (pre v1.7.5) and Prefs:Hiliter (v1.7.5 and later)
  //   deleted.
  DeleteIniSection('Application', gCurrentUserConfigFile);
  DeleteIniSection('SourceOutput', gCurrentUserConfigFile);
  DeleteIniSection('HiliteOutput', gCurrentUserConfigFile);
  for I := 0 to 11 do
    DeleteIniSection('HiliteOutput:Elem' + IntToStr(I), gCurrentUserConfigFile);
  DeleteHighligherPrefs;
  // Main window's overview tabs changed at v3: so we reset to 0 (default)
  SetIniInt('MainWindow', 'OverviewTab', 0, gCurrentUserConfigFile);
end;

// Adds Prefs:CodeGen section along with default data to new installation's user
// config file.
procedure CreateDefaultCodeGenEntries;
begin
  if not FileExists(gCurrentUserConfigFile) then
    CreateUnicodeConfigFile(gCurrentUserConfigFile);
  SetIniInt(
    'Prefs:CodeGen',
    'SwitchOffWarnings',
    0,
    gCurrentUserConfigFile
  );
  SetIniInt(
    'Prefs:CodeGen',
    'WarningCount',
    8,
    gCurrentUserConfigFile
  );
  SetIniString(
    'Prefs:CodeGen',
    'Warning0.Symbol',
    'UNSAFE_TYPE',
    gCurrentUserConfigFile
  );
  SetIniString(
    'Prefs:CodeGen',
    'Warning0.MinCompiler',
    '15.00',
    gCurrentUserConfigFile
  );
  SetIniString(
    'Prefs:CodeGen',
    'Warning1.Symbol',
    'UNSAFE_CAST',
    gCurrentUserConfigFile
  );
  SetIniString(
    'Prefs:CodeGen',
    'Warning1.MinCompiler',
    '15.00',
    gCurrentUserConfigFile
  );
  SetIniString(
    'Prefs:CodeGen',
    'Warning2.Symbol',
    'UNSAFE_CODE',
    gCurrentUserConfigFile
  );
  SetIniString(
    'Prefs:CodeGen',
    'Warning2.MinCompiler',
    '15.00',
    gCurrentUserConfigFile
  );
  SetIniString(
    'Prefs:CodeGen',
    'Warning3.Symbol',
    'SYMBOL_PLATFORM',
    gCurrentUserConfigFile
  );
  SetIniString(
    'Prefs:CodeGen',
    'Warning3.MinCompiler',
    '14.00',
    gCurrentUserConfigFile
  );
  SetIniString(
    'Prefs:CodeGen',
    'Warning4.Symbol',
    'SYMBOL_DEPRECATED',
    gCurrentUserConfigFile
  );
  SetIniString(
    'Prefs:CodeGen',
    'Warning4.MinCompiler',
    '14.00',
    gCurrentUserConfigFile
  );
  SetIniString(
    'Prefs:CodeGen',
    'Warning5.Symbol',
    'SYMBOL_LIBRARY',
    gCurrentUserConfigFile
  );
  SetIniString(
    'Prefs:CodeGen',
    'Warning5.MinCompiler',
    '14.00',
    gCurrentUserConfigFile
  );
  SetIniString(
    'Prefs:CodeGen',
    'Warning6.Symbol',
    'IMPLICIT_STRING_CAST',
    gCurrentUserConfigFile
  );
  SetIniString(
    'Prefs:CodeGen',
    'Warning6.MinCompiler',
    '20.00',
    gCurrentUserConfigFile
  );
  SetIniString(
    'Prefs:CodeGen',
    'Warning7.Symbol',
    'EXPLICIT_STRING_CAST',
    gCurrentUserConfigFile
  );
  SetIniString(
    'Prefs:CodeGen',
    'Warning7.MinCompiler',
    '20.00',
    gCurrentUserConfigFile
  );
end;

// Deletes proxt password entry from new installation's user config file.
procedure DeleteProxyPassword;
begin
  if not FileExists(gCurrentUserConfigFile) then
    CreateUnicodeConfigFile(gCurrentUserConfigFile);
  SetIniString(
    'ProxyServer',
    'Password',
    '',
    gCurrentUserConfigFile
  );
end;

// Checks if current user's config file has a proxy password.
function HasProxyPassword: Boolean;
begin
  Result := GetIniString('ProxyServer', 'Password', '', gCurrentUserConfigFile)
    <> '';
end;

// Deletes config file from given previous installation
procedure DeleteUserCfgFile(InstallID: Integer);
var
  FileName: string;
begin
  FileName := gUserConfigFiles[InstallId];
  if (FileName <> '') and (FileName <> gCurrentUserConfigFile)
    and FileExists(FileName) then
    SysUtils.DeleteFile(FileName);
end;

end.

