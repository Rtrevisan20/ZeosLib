{*********************************************************}
{                                                         }
{                 Zeos Database Objects                   }
{         Sybase SQL Anywhere Connectivity Classes        }
{                                                         }
{        Originally written by Sergey Merkuriev           }
{                                                         }
{*********************************************************}

{@********************************************************}
{    Copyright (c) 1999-2012 Zeos Development Group       }
{                                                         }
{ License Agreement:                                      }
{                                                         }
{ This library is distributed in the hope that it will be }
{ useful, but WITHOUT ANY WARRANTY; without even the      }
{ implied warranty of MERCHANTABILITY or FITNESS FOR      }
{ A PARTICULAR PURPOSE.  See the GNU Lesser General       }
{ Public License for more details.                        }
{                                                         }
{ The source code of the ZEOS Libraries and packages are  }
{ distributed under the Library GNU General Public        }
{ License (see the file COPYING / COPYING.ZEOS)           }
{ with the following  modification:                       }
{ As a special exception, the copyright holders of this   }
{ library give you permission to link this library with   }
{ independent modules to produce an executable,           }
{ regardless of the license terms of these independent    }
{ modules, and to copy and distribute the resulting       }
{ executable under terms of your choice, provided that    }
{ you also meet, for each linked independent module,      }
{ the terms and conditions of the license of that module. }
{ An independent module is a module which is not derived  }
{ from or based on this library. If you modify this       }
{ library, you may extend this exception to your version  }
{ of the library, but you are not obligated to do so.     }
{ If you do not wish to do so, delete this exception      }
{ statement from your version.                            }
{                                                         }
{                                                         }
{ The project web site is located on:                     }
{   http://zeos.firmos.at  (FORUM)                        }
{   http://sourceforge.net/p/zeoslib/tickets/ (BUGTRACKER)}
{   svn://svn.code.sf.net/p/zeoslib/code-0/trunk (SVN)    }
{                                                         }
{   http://www.sourceforge.net/projects/zeoslib.          }
{                                                         }
{                                                         }
{                                 Zeos Development Group. }
{********************************************************@}

unit ZDbcASAStatement;

interface

{$I ZDbc.inc}

{$IFNDEF ZEOS_DISABLE_ASA}
uses Classes, {$IFDEF MSEgui}mclasses,{$ENDIF} SysUtils, FmtBCD,
  ZDbcIntfs, ZDbcStatement, ZCompatibility, ZDbcLogging, ZVariant, ZClasses,
  ZDbcASA, ZDbcASAUtils, ZPlainASADriver, ZPlainASAConstants;

type
  {** Implements Prepared SQL Statement. }
  TZAbstractASAStatement = class(TZRawParamDetectPreparedStatement)
  private
    FCursorOptions: SmallInt;
    FStmtNum: SmallInt;
    FASAConnection: IZASAConnection;
    FPlainDriver: TZASAPlainDriver;
    FInParamSQLDA: PASASQLDA;
    FResultSQLDA: PASASQLDA;
    FSQLData: IZASASQLDA;
    FMoreResults: Boolean;
    FInParamSQLData: IZASASQLDA;
  private
    function CreateResultSet: IZResultSet;
  protected
    procedure CheckParameterIndex(var Value: Integer); override;
  public
    constructor Create(const Connection: IZConnection; const SQL: string; Info: TStrings);
    destructor Destroy; override;

    procedure Prepare; override;
    procedure Unprepare; override;

    procedure AfterClose; override;
    procedure Cancel; override;
    function GetMoreResults: Boolean; override;

    function ExecuteQueryPrepared: IZResultSet; override;
    function ExecuteUpdatePrepared: Integer; override;
    function ExecutePrepared: Boolean; override;
  end;

  TZASAStatement = Class(TZAbstractASAStatement)
  public
    constructor Create(const Connection: IZConnection; Info: TStrings);
  End;

  TZASAPreparedStatement = class(TZAbstractASAStatement, IZPreparedStatement)
  private
    procedure InitBind(SQLVAR: PZASASQLVAR; ASAType: Smallint; Len: Cardinal);
  protected
    procedure BindRawStr(Index: Integer; const Value: RawByteString); override;
    procedure BindRawStr(Index: Integer; Buf: PAnsiChar; Len: LengthInt); override;
    procedure BindLob(Index: Integer; SQLType: TZSQLType; const Value: IZBlob); override;
    procedure BindTimeStampStruct(Index: Integer; ASAType: SmallInt; const Value: TDateTime);
  protected
    procedure PrepareInParameters; override;
    procedure UnPrepareInParameters; override;
    function GetInParamLogValue(Index: Integer): RawByteString; override;
  public
    procedure SetNull(Index: Integer; SQLType: TZSQLType);
    procedure SetBoolean(Index: Integer; Value: Boolean);
    procedure SetByte(Index: Integer; Value: Byte);
    procedure SetShort(Index: Integer; Value: ShortInt);
    procedure SetWord(Index: Integer; Value: Word);
    procedure SetSmall(Index: Integer; Value: SmallInt);
    procedure SetUInt(Index: Integer; Value: Cardinal);
    procedure SetInt(Index: Integer; Value: Integer);
    procedure SetULong(Index: Integer; const Value: UInt64);
    procedure SetLong(Index: Integer; const Value: Int64);
    procedure SetFloat(Index: Integer; Value: Single);
    procedure SetDouble(Index: Integer; const Value: Double);
    procedure SetCurrency(Index: Integer; const Value: Currency);
    procedure SetBigDecimal(Index: Integer; const Value: TBCD);
    procedure SetBytes(Index: Integer; const Value: TBytes); reintroduce;
    procedure SetGuid(Index: Integer; const Value: TGUID); reintroduce;
    procedure SetDate(Index: Integer; const Value: TDateTime); reintroduce;
    procedure SetTime(Index: Integer; const Value: TDateTime); reintroduce;
    procedure SetTimestamp(Index: Integer; const Value: TDateTime); reintroduce;
  end;

  TZASACallableStatement = class(TZAbstractCallableStatement_A, IZCallableStatement)
  protected
    function CreateExecutionStatement(const StoredProcName: String): TZAbstractPreparedStatement; override;
  end;

{$ENDIF ZEOS_DISABLE_ASA}
implementation
{$IFNDEF ZEOS_DISABLE_ASA}

uses ZSysUtils, ZDbcUtils, ZMessages, ZDbcASAResultSet, ZDbcCachedResultSet,
  ZEncoding, ZDbcProperties, ZFastCode;

{ TZAbstractASAStatement }

{**
  Constructs this object and assignes the main properties.
  @param Connection a database connection object.
  @param SQL the query
  @param Info a statement parameters.
}
constructor TZAbstractASAStatement.Create(const Connection: IZConnection;
  const SQL: string; Info: TStrings);
begin
  inherited Create(Connection, SQL, Info);

  FASAConnection := Connection as IZASAConnection;
  FPlainDriver := TZASAPlainDriver(FASAConnection.GetIZPlainDriver.GetInstance);
  FetchSize := BlockSize;
  ResultSetType := rtScrollSensitive;
  CursorName := IntToRaw(NativeUInt(FASAConnection.GetDBHandle))+'_'+IntToRaw(FStatementId);
end;

destructor TZAbstractASAStatement.Destroy;
begin
  inherited Destroy;
  FASAConnection := nil;
end;

function TZAbstractASAStatement.CreateResultSet: IZResultSet;
var
  NativeResultSet: TZASANativeResultSet;
  CachedResultSet: TZCachedResultSet;
begin
  With FASAConnection do begin
    ZDbcASAUtils.CheckASAError(FPlainDriver, GetDBHandle, lcExecute, ConSettings, ASQL);
    FSQLData := TZASASQLDA.Create(FPlainDriver,
      FASAConnection.GetDBHandle, Pointer(CursorName), ConSettings);
    DescribeCursor(FASAConnection, FSQLData, CursorName, ASQL);
    NativeResultSet := TZASANativeResultSet.Create(Self, SQL, FStmtNum, CursorName, FSQLData, CachedLob);
    if ResultSetConcurrency = rcUpdatable then begin
      CachedResultSet := {TZASACachedResultSet}TZCachedResultSet.Create(NativeResultSet, SQL, nil, ConSettings);
      CachedResultSet.SetResolver(TZASACachedResolver.Create(Self, NativeResultSet.GetMetadata));
      CachedResultSet.SetConcurrency(GetResultSetConcurrency);
      Result := CachedResultSet;
    end else
      Result := NativeResultSet;
    FOpenResultSet := Pointer(Result);
  end;
end;

procedure TZAbstractASAStatement.Prepare;
begin
  if not Prepared then
  begin
    with FASAConnection do
    begin
      if FStmtNum <> 0 then
      begin
        FPlainDriver.dbpp_dropstmt(GetDBHandle, nil, nil, @FStmtNum);
        FStmtNum := 0;
      end;
      if ResultSetConcurrency = rcUpdatable then
        FCursorOptions := CUR_OPEN_DECLARE + CUR_UPDATE
      else
        FCursorOptions := CUR_OPEN_DECLARE + CUR_READONLY;
      if ResultSetType = rtScrollInsensitive then
        FCursorOptions := FCursorOptions + CUR_INSENSITIVE;
      FInParamSQLData := TZASASQLDA.Create(FPlainDriver,
        FASAConnection.GetDBHandle, Pointer(CursorName), ConSettings, FCountOfQueryParams);
      FInParamSQLDA := FInParamSQLData.GetData;
      {EH: ASA describes the StmtNum and Variable-Count only
          the first descriptor field is ignored
          also the ParamSQL MUST be given because we wanted to describe the inputparams (even if no types nor names are done)
          else the FMoreResuls indicator does not work properly }
      if Assigned(FPlainDriver.dbpp_prepare_describe_12) then
        FPlainDriver.dbpp_prepare_describe_12(GetDBHandle, nil, nil, @FStmtNum, Pointer(ASQL),
          FResultSQLDA, FInParamSQLDA, SQL_PREPARE_DESCRIBE_STMTNUM +
            SQL_PREPARE_DESCRIBE_INPUT + SQL_PREPARE_DESCRIBE_VARRESULT, 0, 0)
      else
        FPlainDriver.dbpp_prepare_describe(GetDBHandle, nil, nil, @FStmtNum, Pointer(ASQL),
          FResultSQLDA, FInParamSQLDA, SQL_PREPARE_DESCRIBE_STMTNUM +
            SQL_PREPARE_DESCRIBE_INPUT + SQL_PREPARE_DESCRIBE_VARRESULT, 0);
      ZDbcASAUtils.CheckASAError(FPlainDriver, GetDBHandle, lcExecute, GetConSettings, ASQL);
      FMoreResults := GetDBHandle.sqlerrd[2] = 0; //we need to know if more ResultSets can be retrieved
    end;
    inherited Prepare
  end;
end;

procedure TZAbstractASAStatement.Unprepare;
begin
  if not Assigned(FOpenResultSet) then //on closing the RS we exec db_close
    FPlainDriver.dbpp_close(FASAConnection.GetDBHandle, Pointer(CursorName));
  inherited Unprepare;
end;

procedure TZAbstractASAStatement.AfterClose;
begin
  if FStmtNum <> 0 then begin
    FPlainDriver.dbpp_dropstmt(FASAConnection.GetDBHandle, nil, nil, @FStmtNum);
    FStmtNum := 0;
  end;
  FInParamSQLDA := nil;
end;

procedure TZAbstractASAStatement.Cancel;
begin
  with FASAConnection do begin
    FPlainDriver.db_cancel_request(GetDBHandle);
    ZDbcASAUtils.CheckASAError(FPlainDriver, GetDBHandle, lcExecute, ConSettings, ASQL);
  end;
end;

procedure TZAbstractASAStatement.CheckParameterIndex(var Value: Integer);
var I: Integer;
begin
  if not Prepared then
    Prepare;
  if (Value<0) or (Value+1 > BindList.Count) then
    raise EZSQLException.Create(SInvalidInputParameterCount);
  if BindList.HasOutOrInOutOrResultParam then
    for I := 0 to Value do
      if Ord(BindList[I].ParamType) > Ord(pctInOut) then
        Dec(Value);
end;

function TZAbstractASAStatement.GetMoreResults: Boolean;
begin
  Result := FMoreResults;
  if FMoreResults then begin
    with FASAConnection do begin
      FPlainDriver.dbpp_resume(GetDBHandle, Pointer(CursorName));
      ZDbcASAUtils.CheckASAError(FPlainDriver, GetDBHandle, lcExecute, ConSettings);
      if GetDBHandle.sqlcode = SQLE_PROCEDURE_COMPLETE
      then Result := false
      else DescribeCursor(FASAConnection, FSQLData, CursorName, '');
    end;
  end;
end;

{**
  Executes an SQL statement that may return multiple results.
  Under some (uncommon) situations a single SQL statement may return
  multiple result sets and/or update counts.  Normally you can ignore
  this unless you are (1) executing a stored procedure that you know may
  return multiple results or (2) you are dynamically executing an
  unknown SQL string.  The  methods <code>execute</code>,
  <code>getMoreResults</code>, <code>getResultSet</code>,
  and <code>getUpdateCount</code> let you navigate through multiple results.

  The <code>execute</code> method executes an SQL statement and indicates the
  form of the first result.  You can then use the methods
  <code>getResultSet</code> or <code>getUpdateCount</code>
  to retrieve the result, and <code>getMoreResults</code> to
  move to any subsequent result(s).

  @return <code>true</code> if the next result is a <code>ResultSet</code> object;
  <code>false</code> if it is an update count or there are no more results
  @see #getResultSet
  @see #getUpdateCount
  @see #getMoreResults
}
function TZAbstractASAStatement.ExecutePrepared: Boolean;
begin
  Prepare;
  BindInParameters;
  if FMoreResults
  then LastResultSet := ExecuteQueryPrepared
  else begin
    FPlainDriver.dbpp_open(FASAConnection.GetDBHandle, Pointer(CursorName),
      nil, nil, @FStmtNum, FInParamSQLDA, FetchSize, 0, CUR_OPEN_DECLARE + CUR_READONLY);  //need a way to know if a resultset can be retrieved
    if FASAConnection.GetDBHandle.sqlCode = SQLE_OPEN_CURSOR_ERROR then begin
      ExecuteUpdatePrepared;
      FLastResultSet := nil;
    end else
      LastResultSet := CreateResultSet;
  end;
  Result := Assigned(FLastResultSet);
end;

{**
  Executes the SQL query in this <code>PreparedStatement</code> object
  and returns the result set generated by the query.

  @return a <code>ResultSet</code> object that contains the data produced by the
    query; never <code>null</code>
}
function TZAbstractASAStatement.ExecuteQueryPrepared: IZResultSet;
begin
  Prepare;
  PrepareOpenResultSetForReUse;
  BindInParameters;

  with FASAConnection do begin
    FPlainDriver.dbpp_open(GetDBHandle, Pointer(CursorName), nil, nil, @FStmtNum,
      FInParamSQLDA, FetchSize, 0, FCursorOptions);
    if Assigned(FOpenResultSet) then
      Result := IZResultSet(FOpenResultSet)
    else
      Result := CreateResultSet;
  end;
  { Logging SQL Command and values}
  inherited ExecuteQueryPrepared;
end;

{**
  Executes the SQL INSERT, UPDATE or DELETE statement
  in this <code>PreparedStatement</code> object.
  In addition,
  SQL statements that return nothing, such as SQL DDL statements,
  can be executed.

  @return either the row count for INSERT, UPDATE or DELETE statements;
  or 0 for SQL statements that return nothing
}
function TZAbstractASAStatement.ExecuteUpdatePrepared: Integer;
begin
  Prepare;
  BindInParameters;
  with FASAConnection do begin
    FPlainDriver.dbpp_execute_into(GetDBHandle, nil, nil, @FStmtNum,
      FInParamSQLDA, nil);
    ZDbcASAUtils.CheckASAError(FPlainDriver, GetDBHandle, lcExecute, ConSettings,
      ASQL, SQLE_TOO_MANY_RECORDS);
    Result := GetDBHandle.sqlErrd[2];
    LastUpdateCount := Result;
  end;
  { Autocommit statement. }
  if Connection.GetAutoCommit then
    Connection.Commit;
  { Logging SQL Command and values }
  inherited ExecuteUpdatePrepared;
end;

{ TZASAPreparedStatement }

procedure TZASAPreparedStatement.BindLob(Index: Integer; SQLType: TZSQLType;
  const Value: IZBlob);
var ASAType: SmallInt;
  P: Pointer;
  L: LengthInt;
  SQLVAR: PZASASQLVAR;
begin
  inherited BindLob(Index, SQLType, Value); //else FPC raises tons of memleaks
  if (Value = nil) or Value.IsEmpty then
    SetNull(Index{$IFNDEF GENERIC_INDEX}+1{$ENDIF}, SQLType)
  else begin
    P := IZBlob(BindList[Index].Value).GetBuffer;
    L := IZBlob(BindList[Index].Value).Length;
    if SQLType = stBinaryStream
    then ASAType := DT_LONGBINARY
    else ASAType := DT_LONGVARCHAR;
    SQLVAR := @FInParamSQLDA.sqlvar[Index];
    InitBind(SQLVAR, ASAType or 1, L);
    Move(P^, PZASABlobStruct(SQLVAR.sqlData).arr[0], L);
  end;
end;

procedure TZASAPreparedStatement.BindRawStr(Index: Integer;
  const Value: RawByteString);
begin
  if Pointer(Value) <> nil
  then BindRawStr(Index, Pointer(Value), Length(Value))
  else BindRawStr(Index, PEmptyAnsiString, 0);
end;

procedure TZASAPreparedStatement.BindRawStr(Index: Integer; Buf: PAnsiChar;
  Len: LengthInt);
var SQLVAR: PZASASQLVAR;
begin
  CheckParameterIndex(Index);
  SQLVAR := @FInParamSQLDA.sqlvar[Index];
  if (SQLVAR.sqlData = nil) or (SQLVAR.sqlType <> DT_VARCHAR or 1) or (SQLVAR.SQLlen < Len+SizeOf(TZASASQLSTRING)) then
    InitBind(SQLVAR, DT_VARCHAR or 1, Len);
  SQLVAR.sqlind^ := 0; //not NULL
  Move(Buf^, PZASASQLSTRING(SQLVAR.sqlData).data[0], Len);
  PZASASQLSTRING(SQLVAR.sqlData).length := Len;
end;

procedure TZASAPreparedStatement.BindTimeStampStruct(Index: Integer;
  ASAType: SmallInt; const Value: TDateTime);
var SQLVAR: PZASASQLVAR;
  y, m, d: word;
  hr, min, sec, msec: word;
begin
  CheckParameterIndex(Index);
  SQLVAR := @FInParamSQLDA.sqlvar[Index];
  if (SQLVAR.sqlData = nil) or (SQLVAR.sqlType <> DT_TIMESTAMP_STRUCT or 1) then
    InitBind(SQLVAR, DT_TIMESTAMP_STRUCT or 1, SizeOf(TZASASQLDateTime));
  SQLVAR.sqlind^ := 0; //not NULL
  DecodeDate( Value, y, m, d);
  DecodeTime( Value, hr, min, sec, msec);
  PZASASQLDateTime(SQLVAR.sqlData).Year := y;
  PZASASQLDateTime(SQLVAR.sqlData).Month := m - 1;
  PZASASQLDateTime(SQLVAR.sqlData).Day := d;
  PZASASQLDateTime(SQLVAR.sqlData).Hour := hr;
  PZASASQLDateTime(SQLVAR.sqlData).Minute := min;
  PZASASQLDateTime(SQLVAR.sqlData).Second := sec;
  PZASASQLDateTime(SQLVAR.sqlData).MicroSecond := msec * 1000;
  PZASASQLDateTime(SQLVAR.sqlData).Day_of_Week := 0;
  PZASASQLDateTime(SQLVAR.sqlData).Day_of_Year := 0;
  PSmallInt(PAnsiChar(SQLVAR.sqlData)+SizeOf(TZASASQLDateTime))^ := ASAType; //save declared type for the logs
end;

function TZASAPreparedStatement.GetInParamLogValue(
  Index: Integer): RawByteString;
var SQLVAR: PZASASQLVAR;
  DT: TDateTime;
begin
  SQLVAR := @FInParamSQLDA.sqlvar[Index];
  if (SQLVar.sqlInd <> nil) and (SQLVar.sqlInd^ = -1) then
    Result := '(NULL)'
  else case SQLVar.sqlType and $FFFE of
    DT_SMALLINT         : Result := IntToRaw(PSmallInt(SQLVAR.sqlData)^);
    DT_INT              : Result := IntToRaw(PInteger(SQLVAR.sqlData)^);
    //DT_DECIMAL          : ;
    DT_FLOAT            : Result := FloatToRaw(PSingle(SQLVAR.sqldata)^);
    DT_DOUBLE           : Result := FloatToRaw(PDouble(SQLVAR.sqldata)^);
    DT_VARCHAR          : Result := SQLQuotedStr(PAnsiChar(@PZASASQLSTRING(SQLVAR.sqldata).data[0]), PZASASQLSTRING(SQLVAR.sqldata).length, AnsiChar(#39));
    DT_LONGVARCHAR      : Result := '(CLOB)';
    DT_TIMESTAMP_STRUCT : case PSmallInt(PAnsiChar(SQLVAR.sqlData)+SizeOf(TZASASQLDateTime))^ of
                            DT_DATE: Result := ZSysUtils.DateTimeToRawSQLDate(EncodeDate(PZASASQLDateTime(SQLVAR.sqlData).Year,
                              PZASASQLDateTime(SQLVAR.sqlData).Month +1, PZASASQLDateTime(SQLVAR.sqlData).Day), ConSettings.WriteFormatSettings, True);
                            DT_TIME: Result := ZSysUtils.DateTimeToRawSQLTime(EncodeTime(PZASASQLDateTime(SQLVAR.sqlData).Hour,
                              PZASASQLDateTime(SQLVAR.sqlData).Minute, PZASASQLDateTime(SQLVAR.sqlData).Second, PZASASQLDateTime(SQLVAR.sqlData).MicroSecond div 1000), ConSettings.WriteFormatSettings, True);
                            else {DT_TIMESTAMP} begin
                              DT := EncodeDate(PZASASQLDateTime(SQLVAR.sqlData).Year,
                                PZASASQLDateTime(SQLVAR.sqlData).Month +1, PZASASQLDateTime(SQLVAR.sqlData).Day);
                              if DT < 0
                              then DT := DT-EncodeTime(PZASASQLDateTime(SQLVAR.sqlData).Hour,
                                PZASASQLDateTime(SQLVAR.sqlData).Minute, PZASASQLDateTime(SQLVAR.sqlData).Second, PZASASQLDateTime(SQLVAR.sqlData).MicroSecond div 1000)
                              else DT := DT+EncodeTime(PZASASQLDateTime(SQLVAR.sqlData).Hour,
                                PZASASQLDateTime(SQLVAR.sqlData).Minute, PZASASQLDateTime(SQLVAR.sqlData).Second, PZASASQLDateTime(SQLVAR.sqlData).MicroSecond div 1000);
                              Result := ZSysUtils.DateTimeToRawSQLTimeStamp(DT, ConSettings.WriteFormatSettings, True);
                            end;
                          end;
    DT_BINARY           : Result := ZDbcUtils.GetSQLHexAnsiString(PAnsiChar(@PZASASQLSTRING(SQLVAR.sqldata).data[0]), PZASASQLSTRING(SQLVAR.sqldata).length);
    DT_LONGBINARY       : Result := '(BLOB)';
    DT_TINYINT          : Result := IntToRaw(PByte(SQLVAR.sqlData)^);
    DT_BIGINT           : Result := IntToRaw(PInt64(SQLVAR.sqlData)^);
    DT_UNSINT           : Result := IntToRaw(PCardinal(SQLVAR.sqlData)^);
    DT_UNSSMALLINT      : Result := IntToRaw(PWord(SQLVAR.sqlData)^);
    DT_UNSBIGINT        : Result := IntToRaw(PUInt64(SQLVAR.sqlData)^);
    DT_BIT              : If PByte(SQLVAR.sqlData)^ = 0
                          then Result := '(FALSE)'
                          else Result := '(TRUE)';
    DT_NVARCHAR         : Result := SQLQuotedStr(PAnsiChar(@PZASASQLSTRING(SQLVAR.sqldata).data[0]), PZASASQLSTRING(SQLVAR.sqldata).length, AnsiChar(#39));
    DT_LONGNVARCHAR     : Result := '(CLOB)';
    else Result := 'unkown';
  end;
end;

procedure TZASAPreparedStatement.InitBind(SQLVAR: PZASASQLVAR;
  ASAType: Smallint; Len: Cardinal);
begin
  with SQLVAR^ do begin
    if Assigned( sqlData) then
      FreeMem(SQLData);
    case ASAType and $FFFE of
        DT_LONGBINARY, DT_LONGNVARCHAR, DT_LONGVARCHAR: begin
          GetMem(sqlData, Len + SizeOf( TZASABlobStruct));
          PZASABlobStruct( sqlData).array_len := Len;
          PZASABlobStruct( sqlData).stored_len := Len;
          PZASABlobStruct( sqlData).untrunc_len := Len;
          PZASABlobStruct( sqlData).arr[0] := AnsiChar(#0);
          sqllen := SizeOf( TZASABlobStruct)-1;
        end;
      DT_BINARY, DT_VARCHAR, DT_NVARCHAR: begin
          sqllen := Len + SizeOf( TZASASQLSTRING);
          GetMem(sqlData, sqllen);
          PZASASQLSTRING( sqlData).length := 0;
        end;
      DT_DATE, DT_TIME, DT_TIMESTAMP, DT_TIMESTAMP_STRUCT: begin
          sqllen := SizeOf(TZASASQLDateTime);
          GetMem(sqlData, SizeOf(TZASASQLDateTime)+SizeOf(SmallInt));
          PSmallInt(PAnsiChar(SQLData)+SizeOf(TZASASQLDateTime))^ := ASAType; //save declared type
          ASAType := DT_TIMESTAMP_STRUCT or 1;
        end;
      else begin
          GetMem(sqlData, Len);
          sqllen := Len;
        end;
    end;
    sqlType := ASAType;
  end;
end;

procedure TZASAPreparedStatement.PrepareInParameters;
begin
  with FASAConnection do begin
    SetParamCount(FInParamSQLDA.sqld);
    if FInParamSQLDA.sqld <> FInParamSQLDA.sqln then begin
      FInParamSQLData.AllocateSQLDA(FInParamSQLDA.sqld);
      FInParamSQLDA := FInParamSQLData.GetData;
      FPlainDriver.dbpp_describe(GetDBHandle, nil, nil, @FStmtNum,
        FInParamSQLDA, SQL_DESCRIBE_INPUT);
      ZDbcASAUtils.CheckASAError(FPlainDriver, GetDBHandle, lcExecute, GetConSettings, ASQL);
      {sade: initfields doesnt't help > ASA describes !paramcount! only}
    end;
  end;
end;

procedure TZASAPreparedStatement.SetBigDecimal(Index: Integer;
  const Value: TBCD);
begin
  SetRawByteString(Index, BCDToSQLRaw(Value));
end;

procedure TZASAPreparedStatement.SetBoolean(Index: Integer;
  Value: Boolean);
var SQLVAR: PZASASQLVAR;
begin
  {$IFNDEF GENERIC_INDEX}
  Index := Index -1;
  {$ENDIF}
  CheckParameterIndex(Index);
  SQLVAR := @FInParamSQLDA.sqlvar[Index];
  if (SQLVAR.sqlData = nil) or (SQLVAR.sqlType <> DT_BIT or 1) then
    InitBind(SQLVAR, DT_BIT or 1, SizeOf(Byte));
  SQLVAR.sqlind^ := 0; //not NULL
  PByte(SQLVAR.sqlData)^ := Ord(Value);
end;

procedure TZASAPreparedStatement.SetByte(Index: Integer; Value: Byte);
var SQLVAR: PZASASQLVAR;
begin
  {$IFNDEF GENERIC_INDEX}
  Index := Index -1;
  {$ENDIF}
  CheckParameterIndex(Index);
  SQLVAR := @FInParamSQLDA.sqlvar[Index];
  if (SQLVAR.sqlData = nil) or (SQLVAR.sqlType <> DT_TINYINT or 1) then
    InitBind(SQLVAR, DT_TINYINT or 1, SizeOf(Byte));
  SQLVAR.sqlind^ := 0; //not NULL
  PByte(SQLVAR.sqlData)^ := Value;
end;

procedure TZASAPreparedStatement.SetBytes(Index: Integer;
  const Value: TBytes);
var SQLVAR: PZASASQLVAR;
  Len: LengthInt;
begin
  Len := Length(Value);
  if Len = 0 then
    SetNull(Index, stBytes)
  else begin
    {$IFNDEF GENERIC_INDEX}
    Index := Index -1;
    {$ENDIF}
    CheckParameterIndex(Index);
    SQLVAR := @FInParamSQLDA.sqlvar[Index];
    if (SQLVAR.sqlData = nil) or (SQLVAR.sqlType <> DT_BINARY or 1) or (SQLVAR.SQLlen < Len+SizeOf(TZASASQLSTRING)) then
      InitBind(SQLVAR, DT_BINARY or 1, Len);
    SQLVAR.sqlind^ := 0; //not NULL
    Move(Pointer(Value)^, PZASASQLSTRING(SQLVAR.sqlData).data[0], Len);
    PZASASQLSTRING(SQLVAR.sqlData).length := Len;
  end;
end;

procedure TZASAPreparedStatement.SetCurrency(Index: Integer;
  const Value: Currency);
begin
  SetRawByteString(Index, CurrToRaw(Value));
end;

procedure TZASAPreparedStatement.SetDate(Index: Integer;
  const Value: TDateTime);
begin
  BindTimeStampStruct(Index{$IFNDEF GENERIC_INDEX}-1{$ENDIF}, DT_DATE, Value);
end;

procedure TZASAPreparedStatement.SetDouble(Index: Integer;
  const Value: Double);
var SQLVAR: PZASASQLVAR;
begin
  {$IFNDEF GENERIC_INDEX}
  Index := Index -1;
  {$ENDIF}
  CheckParameterIndex(Index);
  SQLVAR := @FInParamSQLDA.sqlvar[Index];
  if (SQLVAR.sqlData = nil) or (SQLVAR.sqlType <> DT_DOUBLE or 1) then
    InitBind(SQLVAR, DT_DOUBLE or 1, SizeOf(Double));
  SQLVAR.sqlind^ := 0; //not NULL
  PDouble(SQLVAR.sqlData)^ := Value;
end;

procedure TZASAPreparedStatement.SetFloat(Index: Integer;
  Value: Single);
var SQLVAR: PZASASQLVAR;
begin
  {$IFNDEF GENERIC_INDEX}
  Index := Index -1;
  {$ENDIF}
  CheckParameterIndex(Index);
  SQLVAR := @FInParamSQLDA.sqlvar[Index];
  if (SQLVAR.sqlData = nil) or (SQLVAR.sqlType <> DT_FLOAT or 1) then
    InitBind(SQLVAR, DT_FLOAT or 1, SizeOf(Single));
  SQLVAR.sqlind^ := 0; //not NULL
  PSingle(SQLVAR.sqlData)^ := Value;
end;

procedure TZASAPreparedStatement.SetGuid(Index: Integer;
  const Value: TGUID);
var SQLVAR: PZASASQLVAR;
begin
  {$IFNDEF GENERIC_INDEX}
  Index := Index -1;
  {$ENDIF}
  CheckParameterIndex(Index);
  SQLVAR := @FInParamSQLDA.sqlvar[Index];
  if (SQLVAR.sqlData = nil) or (SQLVAR.sqlType <> DT_FIXCHAR or 1) or (SQLVAR.SQLlen <> 36) then
    InitBind(SQLVAR, DT_FIXCHAR or 1, 36);
  SQLVAR.sqlind^ := 0; //not NULL
  ZSysUtils.GUIDToBuffer(@Value.D1, PAnsiChar(SQLVAR.sqlData), []);
end;

procedure TZASAPreparedStatement.SetInt(Index, Value: Integer);
var SQLVAR: PZASASQLVAR;
begin
  {$IFNDEF GENERIC_INDEX}
  Index := Index -1;
  {$ENDIF}
  CheckParameterIndex(Index);
  SQLVAR := @FInParamSQLDA.sqlvar[Index];
  if (SQLVAR.sqlData = nil) or (SQLVAR.sqlType <> DT_INT or 1) then
    InitBind(SQLVAR, DT_INT or 1, SizeOf(Integer));
  SQLVAR.sqlind^ := 0; //not NULL
  PInteger(SQLVAR.sqlData)^ := Value;
end;

procedure TZASAPreparedStatement.SetLong(Index: Integer;
  const Value: Int64);
var SQLVAR: PZASASQLVAR;
begin
  {$IFNDEF GENERIC_INDEX}
  Index := Index -1;
  {$ENDIF}
  CheckParameterIndex(Index);
  SQLVAR := @FInParamSQLDA.sqlvar[Index];
  if (SQLVAR.sqlData = nil) or (SQLVAR.sqlType <> DT_BIGINT or 1) then
    InitBind(SQLVAR, DT_BIGINT or 1, SizeOf(Int64));
  SQLVAR.sqlind^ := 0; //not NULL
  PInt64(SQLVAR.sqlData)^ := Value;
end;

procedure TZASAPreparedStatement.SetNull(Index: Integer;
  SQLType: TZSQLType);
var SQLVAR: PZASASQLVAR;
begin
  {$IFNDEF GENERIC_INDEX}
  Index := Index -1;
  {$ENDIF}
  CheckParameterIndex(Index);
  SQLVAR := @FInParamSQLDA.sqlvar[ Index];
  if (SQLVAR.sqlData = nil) or (SQLVAR.sqlType <> SQLType2ASATypeMap[SQLType] or 1) then
    InitBind(SQLVAR, SQLType2ASATypeMap[SQLType] or 1, SQLType2ASASizeMap[SQLType]);
  SQLVAR.sqlind^ := -1 //NULL
end;

procedure TZASAPreparedStatement.SetShort(Index: Integer;
  Value: ShortInt);
begin
  SetSmall(Index, Value);
end;

procedure TZASAPreparedStatement.SetSmall(Index: Integer;
  Value: SmallInt);
var SQLVAR: PZASASQLVAR;
begin
  {$IFNDEF GENERIC_INDEX}
  Index := Index -1;
  {$ENDIF}
  CheckParameterIndex(Index);
  SQLVAR := @FInParamSQLDA.sqlvar[Index];
  if (SQLVAR.sqlData = nil) or (SQLVAR.sqlType <> DT_SMALLINT or 1) then
    InitBind(SQLVAR, DT_SMALLINT or 1, SizeOf(SmallInt));
  SQLVAR.sqlind^ := 0; //not NULL
  PSmallInt(SQLVAR.sqlData)^ := Value;
end;

procedure TZASAPreparedStatement.SetTime(Index: Integer;
  const Value: TDateTime);
begin
  BindTimeStampStruct(Index{$IFNDEF GENERIC_INDEX}-1{$ENDIF}, DT_TIME, Value);
end;

procedure TZASAPreparedStatement.SetTimestamp(Index: Integer;
  const Value: TDateTime);
begin
  BindTimeStampStruct(Index{$IFNDEF GENERIC_INDEX}-1{$ENDIF}, DT_TIMESTAMP, Value);
end;

procedure TZASAPreparedStatement.SetUInt(Index: Integer;
  Value: Cardinal);
var SQLVAR: PZASASQLVAR;
begin
  {$IFNDEF GENERIC_INDEX}
  Index := Index -1;
  {$ENDIF}
  CheckParameterIndex(Index);
  SQLVAR := @FInParamSQLDA.sqlvar[Index];
  if (SQLVAR.sqlData = nil) or (SQLVAR.sqlType <> DT_UNSINT or 1) then
    InitBind(SQLVAR, DT_UNSINT or 1, SizeOf(Cardinal));
  SQLVAR.sqlind^ := 0; //not NULL
  PCardinal(SQLVAR.sqlData)^ := Value;
end;

procedure TZASAPreparedStatement.SetULong(Index: Integer;
  const Value: UInt64);
var SQLVAR: PZASASQLVAR;
begin
  {$IFNDEF GENERIC_INDEX}
  Index := Index -1;
  {$ENDIF}
  CheckParameterIndex(Index);
  SQLVAR := @FInParamSQLDA.sqlvar[Index];
  if (SQLVAR.sqlData = nil) or (SQLVAR.sqlType <> DT_UNSBIGINT or 1) then
    InitBind(SQLVAR, DT_UNSBIGINT or 1, SizeOf(UInt64));
  SQLVAR.sqlind^ := 0; //not NULL
  PUInt64(SQLVAR.sqlData)^ := Value;
end;

procedure TZASAPreparedStatement.SetWord(Index: Integer; Value: Word);
var SQLVAR: PZASASQLVAR;
begin
  {$IFNDEF GENERIC_INDEX}
  Index := Index -1;
  {$ENDIF}
  CheckParameterIndex(Index);
  SQLVAR := @FInParamSQLDA.sqlvar[Index];
  if (SQLVAR.sqlData = nil) or (SQLVAR.sqlType <> DT_UNSSMALLINT or 1) then
    InitBind(SQLVAR, DT_UNSSMALLINT or 1, SizeOf(Word));
  SQLVAR.sqlind^ := 0; //not NULL
  PWord(SQLVAR.sqlData)^ := Value;
end;

procedure TZASAPreparedStatement.UnPrepareInParameters;
begin
  inherited;
  FInParamSQLDA := nil;
end;

{ TZASAStatement }

{**
  Constructs this object and assignes the main properties.
  @param Connection a database connection object.
  @param Info a statement parameters.
}
constructor TZASAStatement.Create(const Connection: IZConnection;
  Info: TStrings);
begin
  inherited Create(Connection, '', Info);
end;

{ TZASACallableStatement }

function TZASACallableStatement.CreateExecutionStatement(
  const StoredProcName: String): TZAbstractPreparedStatement;
var
  I: Integer;
  P: PChar;
  SQL: {$IF defined(FPC) and defined(WITH_RAWBYTESTRING)}RawByteString{$ELSE}String{$IFEND};
begin
  SQL := '';
  ToBuff('CALL ', SQL);
  ToBuff(StoredProcName, SQL);
  if BindList.Count > 0 then
    ToBuff(Char('('), SQL);
  for i := 0 to BindList.Count-1 do
    if BindList.ParamTypes[i] <> pctReturn then
      ToBuff('?,', SQL);
  FlushBuff(SQL);
  P := Pointer(SQL);
  if (P+Length(SQL)-1)^ = ','
  then (P+Length(SQL)-1)^ := ')' //cancel last comma
  else (P+Length(SQL)-1)^ := ' ';
  if IsFunction then
    SQL := SQL +' as ReturnValue';
  Result := TZASAPreparedStatement.Create(Connection , SQL, Info);
  TZASAPreparedStatement(Result).Prepare;
end;

{$ENDIF ZEOS_DISABLE_ASA}
end.



