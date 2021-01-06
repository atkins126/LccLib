unit lcc_ethernet_server;

{$IFDEF FPC}
{$mode objfpc}{$H+}
{$ENDIF}

{$IFDEF FPC}
  {$IFNDEF FPC_CONSOLE_APP}
  //  {$DEFINE LOGGING}
  {$ENDIF}
{$ENDIF}

interface

{$I lcc_compilers.inc}

uses
  Classes,
  SysUtils,
  {$IFDEF FPC}
    {$IFNDEF FPC_CONSOLE_APP} LResources, Forms, Controls, Graphics, Dialogs, {$ENDIF}
  {$ELSE}
  FMX.Forms, Types, System.Generics.Collections,
  {$ENDIF}
  {$IFDEF LOGGING}
  frame_lcc_logging,
  lcc_detailed_logging,
  {$ENDIF}

  {$IFDEF ULTIBO}
  lcc_threaded_stringlist,
  Winsock2,
  Console,
  {$ELSE}
  blcksock,
  synsock,
  Synautil,
  {$ENDIF}
  lcc_gridconnect,
  lcc_utilities,
  lcc_defines,
  lcc_node_manager,
  lcc_node_messages,
  lcc_ethernet_client,
  lcc_app_common_settings,
  lcc_node_messages_can_assembler_disassembler,
  lcc_common_classes,
  lcc_ethernet_common;

type
  TLccEthernetServerThread = class;     // Forward
  TLccEthernetServer = class;

  { TLccEthernetServerThread }

  TLccEthernetServerThread =  class(TLccBaseEthernetThread)
  protected
    procedure ReceiveMessage; override;
    procedure Execute; override;
  end;

  { TLccEthernetListener }

  TLccEthernetListener = class(TLccConnectionThread)
  private
    {$IFDEF ULTIBO}
    FStringList: TThreadStringList;
    FTcpServer: TWinsock2TCPServer;
    {$ELSE}
    FSocket: TTCPBlockSocket;
    {$ENDIF}
    function GetIsTerminated: Boolean;
  protected
    property Running: Boolean read FRunning write FRunning;
    {$IFDEF ULTIBO}
    property StringList: TThreadStringList read FStringList write FStringList;
    property TcpServer: TWinsock2TCPServer read FTcpServer write FTcpServer;
    {$ELSE}
    property Socket: TTCPBlockSocket read FSocket write FSocket;
    {$ENDIF}
    property IsTerminated: Boolean read GetIsTerminated;

    {$IFDEF ULTIBO}
    {$ELSE}
    function CreateServerThread(ASocketHandle: TSocket): TLccEthernetServerThread;
    function CreateThreadObject: TLccEthernetServerThread; virtual;
    {$ENDIF}
    procedure Execute; override;
    procedure SendMessage(AMessage: TLccMessage); override;
    procedure ReceiveMessage; override;
  public
  end;

  { TLccEthernetServer }

  TLccEthernetServer = class(TLccEthernetHardwareConnectionManager)
  private
    FHub: Boolean;
    FListenerThread: TLccEthernetListener;
    { Private declarations }
  protected
    { Protected declarations }
    function GetConnected: Boolean; override;
    function CreateListenerObject(AConnectionInfo: TLccEthernetConnectionInfo): TLccEthernetListener; virtual;
    function IsLccLink: Boolean; override;
  public
    { Public declarations }
    constructor Create(AOwner: TComponent; ANodeManager: TLccNodeManager); override;
    destructor Destroy; override;

    function OpenConnection(AConnectionInfo: TLccHardwareConnectionInfo): TLccConnectionThread; override;
    procedure CloseConnection(EthernetThread: TLccConnectionThread);  override;

    property ListenerThread: TLccEthernetListener read FListenerThread write FListenerThread;

  published
    { Published declarations }
    property Hub: Boolean read FHub write FHub;
  end;


procedure Register;

implementation

procedure Register;
begin
  {$IFNDEF FPC_CONSOLE_APP}
  {$IFDEF FPC}
 //JDK {$I TLccEthernetServer.lrs}
  {$ENDIF}
  RegisterComponents('LCC',[TLccEthernetServer]);
  {$ENDIF}
end;


{ TLccEthernetListener }

{$IFDEF ULTIBO}
{$ELSE}
function TLccEthernetListener.CreateServerThread(ASocketHandle: TSocket): TLccEthernetServerThread;
begin
  Result := CreateThreadObject;
  Result.ListenerSocketHandle := ASocketHandle;    // Back create the sockets with this handle
  Result.Start;
end;

function TLccEthernetListener.CreateThreadObject: TLccEthernetServerThread;
begin
  Result := TLccEthernetServerThread.Create(True, Owner, ConnectionInfo);
end;

{$ENDIF}


{$IFDEF ULTIBO}
procedure TLccEthernetListener.Execute;
begin

end;
{$ELSE}
procedure TLccEthernetListener.Execute;


  procedure SendConnectionNotification(NewConnectionState: TLccConnectionState);
  begin
    ConnectionInfo.ConnectionState := NewConnectionState;
    Synchronize({$IFDEF FPC}@{$ENDIF}ConnectionStateChange);
  end;

  procedure HandleErrorAndDisconnect;
  begin
    Owner.ConnectionThreads.Remove(Self);
    ConnectionInfo.ErrorCode := Socket.LastError;
    ConnectionInfo.MessageStr := Socket.LastErrorDesc;
    Synchronize({$IFDEF FPC}@{$ENDIF}ErrorMessage);
    SendConnectionNotification(lcsDisconnected);
    Terminate
  end;

var
  NewLink: TLccEthernetServerThread;
begin
  FRunning := True;

  Socket := TTCPBlockSocket.Create;          // Created in context of the thread
  Socket.Family := SF_IP4;                  // IP4
  Socket.ConvertLineEnd := True;            // Use #10, #13, or both to be a "string"
  Socket.HeartbeatRate := (ConnectionInfo as TLccEthernetConnectionInfo).HeartbeatRate;
  Socket.SetTimeout(0);
  SendConnectionNotification(lcsConnecting);

  if (ConnectionInfo as TLccEthernetConnectionInfo).AutoResolveIP then
  begin
    {$IFDEF LCC_WINDOWS}
    (ConnectionInfo as TLccEthernetConnectionInfo).ListenerIP := ResolveWindowsIp(Socket);
    {$ELSE}
    (ConnectionInfo as TLccEthernetConnectionInfo).ListenerIP := ResolveUnixIp;
    {$ENDIF}
  end;

  Socket.Bind(String( (ConnectionInfo as TLccEthernetConnectionInfo).ListenerIP), String( IntToStr((ConnectionInfo as TLccEthernetConnectionInfo).ListenerPort)));
  if Socket.LastError <> 0 then
  begin
    HandleErrorAndDisconnect;
    Socket.CloseSocket;
    Socket.Free;
    Socket := nil;
    FRunning := False
  end else
  begin
    Socket.Listen;
    if Socket.LastError <> 0 then
    begin
      HandleErrorAndDisconnect;
      Socket.CloseSocket;
      Socket.Free;
      Socket := nil;
      FRunning := False
    end else
    begin
      SendConnectionNotification(lcsConnected);
      try
        try
          while not Terminated and (ConnectionInfo.ConnectionState = lcsConnected) do
          begin
            if Socket.CanRead(1000) then
            begin
              if not Terminated and (Socket.LastError <> WSAETIMEDOUT) then
              begin
                if Socket.LastError = 0 then
                begin
                  NewLink := CreateServerThread(Socket.Accept);
                  if Assigned(NewLink) then
                    Owner.ConnectionThreads.Add(NewLink);
                end else
                  Terminate;
              end
            end
          end;
        finally
          SendConnectionNotification(lcsDisconnecting);
          Socket.CloseSocket;
          Socket.Free;
          Socket := nil;
        end;
      finally
        SendConnectionNotification(lcsDisconnected);
        FRunning := False;
      end;
    end;
  end;
end;

procedure TLccEthernetListener.SendMessage(AMessage: TLccMessage);
begin
  // must override abstract methods
end;

procedure TLccEthernetListener.ReceiveMessage;
begin
  // must override abstract methods
end;

{$ENDIF}

function TLccEthernetListener.GetIsTerminated: Boolean;
begin
  Result := Terminated;
end;

{ TLccEthernetServer }

procedure TLccEthernetServer.CloseConnection(EthernetThread: TLccConnectionThread);
var
  TimeCount: Integer;
begin
  inherited CloseConnection(EthernetThread);

  if Assigned(ListenerThread) then
  begin
    TimeCount := 0;
    ListenerThread.Terminate;
    {$IFDEF ULTIBO}
      // TODO
    {$ELSE}
    if Assigned(ListenerThread.Socket) then
      ListenerThread.Socket.CloseSocket;  // Force out of wait state with an error
    {$ENDIF}
    while ListenerThread.Running do
    begin
      {$IFNDEF FPC_CONSOLE_APP}
      Application.ProcessMessages;
      {$ELSE}
      CheckSynchronize();  // Pump the timers
      {$ENDIF}
      Inc(TimeCount);
      Sleep(100);
      if TimeCount = 10 then
      begin
        {$IFDEF ULTIBO}
        {$ELSE}
         if Assigned(ListenerThread.Socket) then
           ListenerThread.Socket.CloseSocket
         else
           Break // Something went really wrong
        {$ENDIF}
      end;
    end;
    FreeAndNil(FListenerThread);
  end;
end;

function TLccEthernetServer.IsLccLink: Boolean;
begin
  Result := True;
end;

function TLccEthernetServer.GetConnected: Boolean;
begin
  Result := Assigned(ListenerThread)
end;

constructor TLccEthernetServer.Create(AOwner: TComponent; ANodeManager: TLccNodeManager);
begin
  inherited;
  FHub := False;
end;

destructor TLccEthernetServer.Destroy;
begin
  inherited Destroy;
end;

function TLccEthernetServer.OpenConnection(AConnectionInfo: TLccHardwareConnectionInfo): TLccConnectionThread;
begin
  Result := inherited OpenConnection(AConnectionInfo);
  Result := CreateListenerObject(AConnectionInfo.Clone as TLccEthernetConnectionInfo);
  (Result as TLccEthernetListener).Suspended := False;
  ListenerThread := (Result as TLccEthernetListener);
end;

function TLccEthernetServer.CreateListenerObject(AConnectionInfo: TLccEthernetConnectionInfo): TLccEthernetListener;
begin
  Result := TLccEthernetListener.Create(True, Self, AConnectionInfo);
end;

{ TLccEthernetServerThread }

{$IFDEF ULTIBO}
procedure TLccEthernetServerThread.Execute;
begin

end;
{$ELSE}
procedure TLccEthernetServerThread.Execute;
var
  GridConnectHelper: TGridConnectHelper;
  LocalSleepCount: Integer;
begin
  FRunning := True;

  HandleSendConnectionNotification(lcsConnecting);
  GridConnectHelper := TGridConnectHelper.Create;
  Socket := TTCPBlockSocket.Create;          // Created in context of the thread
  Socket.Family := SF_IP4;                  // IP4
  if ConnectionInfo.GridConnect then
    Socket.ConvertLineEnd := True;            // Use #10, #13, or both to be a "string"
  Socket.HeartbeatRate := (ConnectionInfo as TLccEthernetConnectionInfo).HeartbeatRate;
  Socket.SetTimeout(0);
  Socket.Socket := ListenerSocketHandle;    // Read back the handle
  if Socket.LastError <> 0 then
  begin
    HandleErrorAndDisconnect;
    Socket.CloseSocket;
    Socket.Free;
    Socket := nil;
    GridConnectHelper.Free;
    FRunning := False
  end else
  begin
    (ConnectionInfo as TLccEthernetConnectionInfo).ClientIP := Socket.GetRemoteSinIP;
    (ConnectionInfo as TLccEthernetConnectionInfo).ClientPort := Socket.GetRemoteSinPort;
    (ConnectionInfo as TLccEthernetConnectionInfo).ListenerIP := Socket.GetLocalSinIP;
    (ConnectionInfo as TLccEthernetConnectionInfo).ListenerPort := Socket.GetLocalSinPort;
    if Socket.LastError <> 0 then
    begin
      HandleErrorAndDisconnect;
      Socket.CloseSocket;
      Socket.Free;
      Socket := nil;
      GridConnectHelper.Free;
      FRunning := False
    end else
    begin
      HandleSendConnectionNotification(lcsConnected);
      try
        try
          LocalSleepCount := 0;
          while not IsTerminated and (ConnectionInfo.ConnectionState = lcsConnected) do
          begin  // Handle the Socket using GridConnect
            if ConnectionInfo.Gridconnect then
            begin
              if LocalSleepCount >= ConnectionInfo.SleepCount then
              begin
                TryTransmitGridConnect(True);
                LocalSleepCount := 0;
              end;
              Inc(LocalSleepCount);

              TryReceiveGridConnect(GridConnectHelper, True);
            end else
            begin    // Handle the Socket with LCC TCP Protocol
              if LocalSleepCount >= ConnectionInfo.SleepCount then
              begin
                TryTransmitTCPProtocol(True);
                LocalSleepCount := 0;
              end;
              Inc(LocalSleepCount);

              TryReceiveTCPProtocol(True);
            end;
          end;
        finally
          HandleSendConnectionNotification(lcsDisconnecting);
          if ConnectionInfo.Gridconnect then
            TryTransmitGridConnect(False) // Flush it
          else
            TryTransmitTCPProtocol(False);
          Socket.CloseSocket;
          Socket.Free;
          Socket := nil;
          GridConnectHelper.Free;
        end;
      finally
        HandleSendConnectionNotification(lcsDisconnected);
        Owner.ConnectionThreads.Remove(Self);
        FRunning := False;
      end;
    end;
  end;
end;

{$ENDIF}

procedure TLccEthernetServerThread.ReceiveMessage;
var
  L: TList;
  i: Integer;
begin
  // Called in the content of the main thread through Syncronize

  // here is where we call backwards into the Connection Manager that owns this thread.
  // The Connection Manager then call back into the Node Manager.  The Node Manager passes
  // the message to its nodes plus then stars back out to any other Connection Managers
  // that are registered (as we are registered).  The Manager decendant must override
  // IsLccLink and return TRUE in order to be included in this system
  inherited ReceiveMessage;

  // Now we look upwards into any thread we have that depend on use to pass on messages
  // assuming we are a Hub.
  if (Owner as TLccEthernetServer).Hub then
  begin
    L := Owner.ConnectionThreads.LockList;
    try
      for i := 0 to L.Count - 1 do
      begin
        if TLccEthernetServerThread(L[i]) <> Self then
          TLccEthernetServerThread(L[i]).SendMessage(ConnectionInfo.LccMessage);
      end;
    finally
      Owner.ConnectionThreads.UnlockList;
    end
  end;
end;

initialization
  RegisterClass(TLccEthernetServer);

finalization

end.

