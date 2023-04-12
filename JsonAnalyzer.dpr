program JsonAnalyzer;

////////////////////////////////////////////////////////////////////////////////
///  JSON analyzation program                                                ///
///                                                                          ///
///  Written by Dennis Göhlert                                               ///
///  Licensed under Mozilla Public License (MPL) 2.0                         ///
///                                                                          ///
///  Last modified: 12.04.2023 04:00                                         ///
///  (c) 2023 All rights reserved                                            ///
////////////////////////////////////////////////////////////////////////////////

{$APPTYPE CONSOLE}
{$SCOPEDENUMS ON}

{$R *.res}

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  System.IOUtils,
  System.Classes,
  System.JSON.Readers, System.JSON.Builders, System.JSON.Types;

type
  EAnalyzeError = class(Exception);

  TAnalyzationOption = (
    Root,
    Depth,
    Excluded
  );

  TAnalyzationOptionHelper = record helper for TAnalyzationOption
  private
    function GetIdent: String;
  public
    property Ident: String read GetIdent;
  end;

  TAnalyzationOptions = record
  private
    class function GetRoot: String; static;
    class function GetDepth: Integer; static;
    class function GetExcluded: String; static;
  public
    class property Root: String read GetRoot;
    class property Depth: Integer read GetDepth;
    class property Excluded: String read GetExcluded;
  end;

  TAnalyzationProc = procedure (const AJsonIterator: TJSONIterator);

  TAnalyzationMethod = (
    View,
    Count
  );

  TAnalyzationHelper = record helper for TAnalyzationMethod
  private
    class function GetCurrent: TAnalyzationMethod; static;
    function GetIdent: String;
    function GetProc: TAnalyzationProc;
  public
    property Ident: String read GetIdent;
    property Proc: TAnalyzationProc read GetProc;
    class property Current: TAnalyzationMethod read GetCurrent;
    procedure Run(const AJsonIterator: TJSONIterator);
  end;

  TJsonType = (
    Unknown,
    Null,
    Boolean,
    Number,
    &String,
    &Array,
    &Object
  );

  TJsonTypeHelper = record helper for TJsonType
  private
    function GetName: String;
  public
    property Name: String read GetName;
    constructor Create(const AToken: TJsonToken);
  end;

resourcestring
  Error_InvalidRecursionDepth = 'Invalid recursion depth: %s';
  Error_MissingAnalyzation = 'Missing definition for analyzation method (use "-?" switch for help)';
  Error_MissingFileName = 'Missing file name';
  Error_RootNotFound = 'Root node not found: %s';
  Error_DuplicateAnalyzation = 'Duplicate definition for analyzation method';
  Error_InvalidFileName = 'Invalid file name: %s';
  Error_FileNotExists = 'File does not exist: %s';
  Result_Info =
    'Possible modes are:' + sLineBreak +
    ' -? (show help)' + sLineBreak +
    ' -v (view structure)' + sLineBreak +
    ' -c (count sub nodes)' + sLineBreak +
    sLineBreak +
    'Possible options are:' + sLineBreak +
    ' -p ROOT (define path to root node)' + sLineBreak +
    ' -r DEPTH (define recursion depth)' + sLineBreak +
    ' -x KEY (exclude key)';
  Result_Success = 'Analyzation successful';
  Result_Error = 'Error: %s';

{ TAnalyzationOptionHelper }

function TAnalyzationOptionHelper.GetIdent: String;
const
  LIdents: array [TAnalyzationOption] of String = (
    'e', 'r', 'x'
  );
begin
  Result := LIdents[Self];
end;

{ TAnalyzationOptions }

class function TAnalyzationOptions.GetDepth: Integer;
var
  LResult: String;
begin
  if FindCmdLineSwitch(TAnalyzationOption.Depth.Ident, LResult) then
  begin
    if (not Integer.TryParse(LResult, Result)) or (Result < 0) then
    begin
      raise EAnalyzeError.CreateResFmt(@Error_InvalidRecursionDepth, [Result]);
    end;
  end else
  begin
    Result := 0;
  end;
end;

class function TAnalyzationOptions.GetExcluded: String;
begin
  FindCmdLineSwitch(TAnalyzationOption.Excluded.Ident, Result);
end;

class function TAnalyzationOptions.GetRoot: String;
begin
  FindCmdLineSwitch(TAnalyzationOption.Root.Ident, Result);
end;

{ TAnalyzationHelper }

class function TAnalyzationHelper.GetCurrent: TAnalyzationMethod;
var
  LFound: Boolean;
  LAnalyzation: TAnalyzationMethod;
  LValue: String;
begin
  LFound := False;
  for LAnalyzation := Low(TAnalyzationMethod) to High(TAnalyzationMethod) do
  begin
    if FindCmdLineSwitch(LAnalyzation.Ident) then
    begin
      if LFound then
      begin
        raise EAnalyzeError.CreateRes(@Error_DuplicateAnalyzation);
      end;
      LFound := True;
      Result := (LAnalyzation);
    end;
  end;
  if not LFound then
  begin
    raise EAnalyzeError.CreateRes(@Error_MissingAnalyzation);
  end;
end;

function TAnalyzationHelper.GetIdent: String;
const
  LIdents: array [TAnalyzationMethod] of String = (
    'v', 'c'
  );
begin
  Result := LIdents[Self];
end;

function TAnalyzationHelper.GetProc: TAnalyzationProc;

  procedure ViewAll(const AJsonIterator: TJSONIterator);
  var
    LDepth: Integer;

    procedure View;
    begin
      while AJsonIterator.Next do
      begin
        Writeln(String.Format('%s'#$2017 + IfThen(not AJsonIterator.Key.IsEmpty, ' ') + '%s (%s)', [DupeString(' '#$2551, LDepth), AJsonIterator.Key, TJsonType.Create(AJsonIterator.&Type).Name]));
        if ((TAnalyzationOptions.Depth = 0) or (TAnalyzationOptions.Depth > LDepth)) and (AJsonIterator.Key.IsEmpty or TAnalyzationOptions.Excluded.IsEmpty or not AJsonIterator.Key.Equals(TAnalyzationOptions.Excluded)) then
        begin
          if AJsonIterator.Recurse then
          begin
            Inc(LDepth);
            View;
            AJsonIterator.Return;
            Dec(LDepth);
          end;
        end;
      end;
    end;

  begin
    LDepth := 1;
    Writeln('(object)');
    View;
  end;

  procedure CountAll(const AJsonIterator: TJSONIterator);
  type
    TCounts = array [TJsonType] of Integer;
  var
    LDepth: Integer;
    LCounts: TCounts;
    LType: TJsonType;

    procedure Count;
    begin
      while AJsonIterator.Next do
      begin
        Inc(LCounts[TJsonType.Create(AJsonIterator.&Type)]);
        if ((TAnalyzationOptions.Depth = 0) or (TAnalyzationOptions.Depth > LDepth)) and (AJsonIterator.Key.IsEmpty or TAnalyzationOptions.Excluded.IsEmpty or not AJsonIterator.Key.Equals(TAnalyzationOptions.Excluded)) then
        begin
          if AJsonIterator.Recurse then
          begin
            Inc(LDepth);
            Count;
            AJsonIterator.Return;
            Dec(LDepth);
          end;
        end;
      end;
    end;

  begin
    LDepth := 1;
    LCounts := Default(TCounts);
    Count;
    Writeln(String.Format('Total: %d nodes', [SumInt(LCounts)]));
    Writeln;
    for LType := Low(TJsonType) to High(TJsonType) do
    begin
      Writeln(String.Format('%d (%s)', [LCounts[LType], LType.Name]));
    end;
  end;

begin
  case Self of
    TAnalyzationMethod.View:
      begin
        Result := @ViewAll;
      end;
    TAnalyzationMethod.Count:
      begin
        Result := @CountAll;
      end;
  end;
end;

procedure TAnalyzationHelper.Run(const AJsonIterator: TJSONIterator);
var
  LRoot: String;
begin
  LRoot := TAnalyzationOptions.Root;
  if not LRoot.IsEmpty then
  begin
    if not AJsonIterator.Find(LRoot) then
    begin
      raise EAnalyzeError.CreateResFmt(@Error_RootNotFound, [LRoot]);
    end;
    AJsonIterator.Recurse;
  end;
  Proc(AJsonIterator);
  Writeln;
  Writeln(Result_Success);
end;

{ TJsonTypeHelper }

constructor TJsonTypeHelper.Create(const AToken: TJsonToken);
begin
  case AToken of
    TJsonToken.StartObject:
      begin
        Self := TJsonType.Object;
      end;
    TJsonToken.StartArray:
      begin
        Self := TJsonType.Array;
      end;
    TJsonToken.Integer,
    TJsonToken.Float:
      begin
        Self := TJsonType.Number;
      end;
    TJsonToken.String:
      begin
        Self := TJsonType.String;
      end;
    TJsonToken.Boolean:
      begin
        Self := TJsonType.Boolean;
      end;
    TJsonToken.Null:
      begin
        Self := TJsonType.Null;
      end;
  else
    begin
      Self := TJsonType.Unknown;
    end;
  end;
end;

function TJsonTypeHelper.GetName: String;
const
  LNames: array [TJsonType] of String = (
    '???', 'null', 'boolean', 'number', 'string', 'array', 'object'
  );
begin
  Result := LNames[Self];
end;

var
  FileName: String;
  FileStream: TFileStream;
  StreamReader: TStreamReader;
  JsonReader: TJsonTextReader;
  JsonIterator: TJSONIterator;
begin
  try
    FileName := ParamStr(1);
    if FileName.IsEmpty or FileName.StartsWith('-') or FileName.StartsWith('/') then
    begin
      raise EAnalyzeError.CreateRes(@Error_MissingFileName);
    end;
    if not TPath.HasValidPathChars(FileName, False) then
    begin
      raise EAnalyzeError.CreateResFmt(@Error_InvalidFileName, [FileName]);
    end;
    if not TFile.Exists(FileName) then
    begin
      raise EAnalyzeError.CreateResFmt(@Error_FileNotExists, [FileName]);
    end;
    FileStream := TFile.OpenRead(FileName);
    try
      StreamReader := TStreamReader.Create(FileStream);
      try
        JsonReader := TJsonTextReader.Create(StreamReader);
        try
          JsonIterator := TJSONIterator.Create(JsonReader,
            procedure (AReader: TJsonReader)
            begin
              FileStream.Position := 0;
            end
          );
          try
            if FindCmdLineSwitch('?') then
            begin
              Writeln(Result_Info);
            end else
            begin
              TAnalyzationMethod.Current.Run(JsonIterator);
            end;
          finally
            JsonIterator.Free;
          end;
        finally
          JsonReader.Free;
        end;
      finally
        StreamReader.Free;
      end;
    finally
      FileStream.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln(String.Format(Result_Error, [E.Message]));
    end;
  end;
end.
