unit lcc_protocol_base;

interface

uses
{$IFDEF DWSCRIPT}
  System.Types,
  System.Types.Convert,
  System.Time,
  System.Streams,
  System.Reader,
  System.Writer,
  System.Lists,
  System.Device.Storage,
  SmartCL.Device.Storage,
  SmartCL.Application,
  SmartCL.Components,
  SmartCL.System,
{$ELSE}
  Classes,
  SysUtils,
{$ENDIF}
  lcc_defines,
  lcc_node_messages;

type

{ TNodeProtocolBase }

TNodeProtocolBase = class(TObject)
private
//JDK  FCreateTime: DWord;    Not sure what I used this for
  FErrorCode: Word;
  FSendMessageFunc: TLccSendMessageFunc;
  FWorkerMessage: TLccMessage;
protected
  FValid: Boolean;
  procedure SetValid(AValue: Boolean); virtual;  // Just so it can be overridden for special behavior
//JDK  property CreateTime: DWord read FCreateTime write FCreateTime;
  property WorkerMessage: TLccMessage read FWorkerMessage write FWorkerMessage;
public
  property SendMessageFunc: TLccSendMessageFunc read FSendMessageFunc;
  property ErrorCode: Word read FErrorCode write FErrorCode;
  property Valid: Boolean read FValid write SetValid;

  constructor Create(ASendMessageFunc: TLccSendMessageFunc); virtual;
  destructor Destroy; override;

  function ProcessMessage(SourceLccMessage: TLccMessage): Boolean; virtual;
  procedure LoadFromLccMessage(SourceLccMessage: TLccMessage); virtual;
end;

{ TStreamBasedProtocol }

TStreamBasedProtocol = class(TNodeProtocolBase)
private
  FInProcessAddress: DWord;
  FNullTerminatedString: Boolean;
  FStream: TMemoryStream;
  FAddressSpace: Byte;
protected
  procedure SetValid(AValue: Boolean); override;
  procedure DoLoadComplete(LccMessage: TLccMessage); virtual;

  property InProcessAddress: DWord read FInProcessAddress write FInProcessAddress;
  property AddressSpace: Byte read FAddressSpace write FAddressSpace;
  property NullTerminatedString: Boolean read FNullTerminatedString write FNullTerminatedString;
public
  property AStream: TMemoryStream read FStream write FStream;

  constructor Create(ASendMessageFunc: TLccSendMessageFunc; AnAddressSpace: Byte; IsStringBasedStream: Boolean); reintroduce; virtual;
  destructor Destroy; override;

  procedure LoadReply(LccMessage: TLccMessage; OutMessage: TLccMessage); virtual;
  procedure WriteRequest(LccMessage: TLccMessage); virtual;
  function ProcessMessage(SourceLccMessage: TLccMessage): Boolean; override;
end;

implementation

{ TNodeProtocolBase }

procedure TNodeProtocolBase.SetValid(AValue: Boolean);
begin
  if FValid=AValue then Exit;
  FValid:=AValue;
end;

constructor TNodeProtocolBase.Create(ASendMessageFunc: TLccSendMessageFunc);
begin
  inherited Create;
//JDK  FCreateTime := GetTickCount;
  FSendMessageFunc := ASendMessageFunc;
  FWorkerMessage := TLccMessage.Create;
end;

destructor TNodeProtocolBase.Destroy;
begin
  FWorkerMessage.Free;
  inherited Destroy;
end;

function TNodeProtocolBase.ProcessMessage(SourceLccMessage: TLccMessage): Boolean;
begin

end;

procedure TNodeProtocolBase.LoadFromLccMessage(SourceLccMessage: TLccMessage);
begin
  // Do nothing must override to implement
end;

{ TStreamBasedProtocol }

procedure TStreamBasedProtocol.SetValid(AValue: Boolean);
begin
  inherited SetValid(AValue);
  if not AValue then
  begin
    AStream.Size := 0;
    InProcessAddress := 0;
  end
end;

procedure TStreamBasedProtocol.WriteRequest(LccMessage: TLccMessage);
begin

end;

constructor TStreamBasedProtocol.Create(ASendMessageFunc: TLccSendMessageFunc; AnAddressSpace: Byte; IsStringBasedStream: Boolean);
begin
  inherited Create(ASendMessageFunc);
  FStream := TMemoryStream.Create;
  FAddressSpace := AnAddressSpace;
  IsStringBasedStream := NullTerminatedString;
end;

destructor TStreamBasedProtocol.Destroy;
begin
  FStream.Free;
  inherited Destroy;
end;

procedure TStreamBasedProtocol.DoLoadComplete(LccMessage: TLccMessage);
begin

end;

procedure TStreamBasedProtocol.LoadReply(LccMessage: TLccMessage; OutMessage: TLccMessage);
var
  i: Integer;
  iStart, ReadCount: Integer;
  AByte: Byte;
  Address: DWord;
begin
  // Assumption is this is a datagram message
  if LccMessage.DataArrayIndexer[1] and $03 = 0 then
    iStart := 7
  else
    iStart := 6;
  ReadCount := LccMessage.DataArrayIndexer[iStart];
  OutMessage.DataArrayIndexer[0] := LccMessage.DataArrayIndexer[0];
  OutMessage.DataArrayIndexer[1] := LccMessage.DataArrayIndexer[1] or $10;   // Make it a reply
  OutMessage.DataArrayIndexer[2] := LccMessage.DataArrayIndexer[2];    // Copy the address
  OutMessage.DataArrayIndexer[3] := LccMessage.DataArrayIndexer[3];
  OutMessage.DataArrayIndexer[4] := LccMessage.DataArrayIndexer[4];
  OutMessage.DataArrayIndexer[5] := LccMessage.DataArrayIndexer[5];
  if iStart = 7 then
    OutMessage.DataArrayIndexer[6] := LccMessage.DataArrayIndexer[6];

  Address := LccMessage.ExtractDataBytesAsInt(2, 5);
  if AStream.Size < Address + ReadCount then
  begin
    AStream.Position := AStream.Size;
    for i := 0 to ((Address + ReadCount) - AStream.Size) - 1 do
      {$IFDEF FPC}
      AStream.WriteByte(0);
     {$ELSE}
      AByte := 0;
//JDK

//      AStream.Write(AByte, 1);
     {$ENDIF}
  end;

  if AStream.Size = 0 then
  begin
    OutMessage.DataCount := iStart + 1;
    OutMessage.DataArrayIndexer[iStart] := Ord(#0);
  end else
  begin
    AStream.Position := Address;
    i := 0;
    while (AStream.Position < AStream.Size) and (i < ReadCount) do
    begin
      AByte := 0;

    //JDK

    //  AStream.Read(AByte, 1);
      OutMessage.DataArrayIndexer[iStart + i] := AByte;
      Inc(i);
    end;
    OutMessage.DataCount := iStart + i;

    if NullTerminatedString then
    begin
      if AStream.Position = AStream.Size then
      begin
        OutMessage.DataArrayIndexer[OutMessage.DataCount] := Ord(#0);
        OutMessage.DataCount := OutMessage.DataCount + 1
      end;
    end;
  end;
  OutMessage.UserValid := True;
end;

function TStreamBasedProtocol.ProcessMessage(SourceLccMessage: TLccMessage): Boolean;
var
  NullFound: Boolean;
  i: Integer;
  iStart: Integer;
  AByte: Byte;
begin
  Result := True;
  if not Valid then
  begin
    NullFound := False;
    if SourceLccMessage.DataArrayIndexer[1] and $03 = 0 then
      iStart := 7
    else
      iStart := 6;
    for i := iStart to SourceLccMessage.DataCount - 1 do
    begin
      NullFound := SourceLccMessage.DataArrayIndexer[i] = Ord(#0);
      AByte := SourceLccMessage.DataArrayIndexer[i];

  //JDK
   //   AStream.WriteBuffer(AByte, 1);

      if NullFound then
        Break
    end;

    if NullFound then
    begin
      AStream.Position := 0;
      FValid := True;
      DoLoadComplete(SourceLccMessage);
    end else
    begin
      WorkerMessage.IsCAN := False;
      WorkerMessage.SourceID := SourceLccMessage.DestID;
      WorkerMessage.CAN.SourceAlias := SourceLccMessage.CAN.DestAlias;
      WorkerMessage.DestID := SourceLccMessage.SourceID;
      WorkerMessage.CAN.DestAlias := SourceLccMessage.CAN.SourceAlias;
      WorkerMessage.DataCount := 0;
      WorkerMessage.DataArrayIndexer[0] := DATAGRAM_PROTOCOL_CONFIGURATION;
      WorkerMessage.DataArrayIndexer[1] := MCP_READ;
      InProcessAddress := InProcessAddress + 64 {- iStart};
      WorkerMessage.InsertDWordAsDataBytes(InProcessAddress, 2);
      WorkerMessage.DataArrayIndexer[6] := AddressSpace;
      WorkerMessage.DataArrayIndexer[7] := 64;                     // Read until the end.....
      WorkerMessage.DataCount := 8;
      WorkerMessage.MTI := MTI_DATAGRAM;
  //JDK    OwnerManager.DoRequestMessageSend(WorkerMessage);
    end;
  end;
end;

end.

