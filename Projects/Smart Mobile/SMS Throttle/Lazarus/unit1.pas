unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  Forms,
  Controls,
  Graphics,
  Dialogs,
  StdCtrls,
  ComCtrls,
  SynEdit,
  lcc_utilities,
  lcc_node,
  lcc_node_manager,
  lcc_node_messages,
  lcc_defines,
  lcc_ethernet_server,
  lcc_ethernet_client,
  lcc_protocol_memory_configurationdefinitioninfo;

type

  { TForm1 }

  TForm1 = class(TForm)
    Button1: TButton;
    Button2: TButton;
    Button3: TButton;
    ButtonDatagramCount: TButton;
    CheckBoxLogging: TCheckBox;
    LabelAllcoatedDatagrams: TLabel;
    StatusBar1: TStatusBar;
    SynEdit1: TSynEdit;
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure Button3Click(Sender: TObject);
    procedure ButtonDatagramCountClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: boolean);
    procedure FormCreate(Sender: TObject);
  private

  public
    EthernetServer: TLccEthernetServer;
    CanNodeManager: TLccCanNodeManager;
    procedure OnEthernetConnectionChange(Sender: TObject; EthernetRec: TLccEthernetRec);
    procedure SendMessage(Sender: TObject; LccMessage: TLccMessage);
    procedure ReceiveMessage(Sender: TObject; LccMessage: TLccMessage);
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

procedure TForm1.Button1Click(Sender: TObject);
var
  EthernetRec: TLccEthernetRec;
begin
  FillChar(EthernetRec, Sizeof(EthernetRec), #0);
  EthernetServer.OnConnectionStateChange := @OnEthernetConnectionChange;
  EthernetRec.ListenerIP := '127.0.0.1';
//  EthernetRec.AutoResolveIP := True;
  EthernetRec.ListenerPort := 12021;
  if EthernetServer.Connected then
  begin
    CanNodeManager.LogoutAll;
    EthernetServer.CloseConnection(nil);
    Button1.Caption := 'Connect';
  end else
  begin
    EthernetServer.OpenConnection(EthernetRec);
    Button1.Caption := 'Disconnect';
  end;
end;

procedure TForm1.Button2Click(Sender: TObject);
var
  CanNode: TLccCanNode;
begin
  if CanNodeManager.Nodes.Count = 0 then
  begin
    CanNode := CanNodeManager.AddNode(CDI_XML) as TLccCanNode;
    CanNode.ProtocolSupportedProtocols.CDI := True;
    CanNode.ProtocolSupportedProtocols.Datagram := True;
    CanNode.ProtocolSupportedProtocols.EventExchange := True;
    CanNode.ProtocolSupportedProtocols.SimpleNodeInfo := True;

    CanNode.ProtocolMemoryInfo.Add(MSI_CDI, True, True, True, 0, $FFFFFFFF);
    CanNode.ProtocolMemoryInfo.Add(MSI_ALL, True, True, True, 0, $FFFFFFFF);
    CanNode.ProtocolMemoryInfo.Add(MSI_CONFIG, True, False, True, 0, $FFFFFFFF);

    CanNode.ProtocolMemoryOptions.WriteUnderMask := True;
    CanNode.ProtocolMemoryOptions.UnAlignedReads := True;
    CanNode.ProtocolMemoryOptions.UnAlignedWrites := True;
    CanNode.ProtocolMemoryOptions.SupportACDIMfgRead := True;
    CanNode.ProtocolMemoryOptions.SupportACDIUserRead := True;
    CanNode.ProtocolMemoryOptions.SupportACDIUserWrite := True;
    CanNode.ProtocolMemoryOptions.WriteLenOneByte := True;
    CanNode.ProtocolMemoryOptions.WriteLenTwoBytes := True;
    CanNode.ProtocolMemoryOptions.WriteLenFourBytes := True;
    CanNode.ProtocolMemoryOptions.WriteLenSixyFourBytes := True;
    CanNode.ProtocolMemoryOptions.WriteArbitraryBytes := True;
    CanNode.ProtocolMemoryOptions.WriteStream := False;
    CanNode.ProtocolMemoryOptions.HighSpace := MSI_CDI;
    CanNode.ProtocolMemoryOptions.LowSpace := MSI_CONFIG;

    CanNode.ProtocolEventConsumed.AutoGenerate.Count := 5;
    CanNode.ProtocolEventConsumed.AutoGenerate.StartIndex := 0;

    CanNode.ProtocolEventsProduced.AutoGenerate.Count := 5;
    CanNode.ProtocolEventsProduced.AutoGenerate.StartIndex := 0;

    CanNode.Login(NULL_NODE_ID); // Create our own ID

    lcc_defines.Max_Allowed_Buffers := 1; // HACK ALLERT: Allow OpenLCB Python Scripts to run

  end else
    CanNodeManager.Clear;
end;

procedure TForm1.Button3Click(Sender: TObject);
begin
  SynEdit1.Clear;
end;

type
  TLccCanNodeHack = class(TLccCanNode);

procedure TForm1.ButtonDatagramCountClick(Sender: TObject);
var
  Msg: TLccMessage;
begin
  if CanNodeManager.Nodes.Count > 0 then
  begin
    if TLccCanNodeHack( CanNodeManager.Nodes[0]).InProcessMultiFrameMessage.Count > 0 then
    begin
      Msg := TLccMessage(TLccCanNodeHack( CanNodeManager.Nodes[0]).InProcessMultiFrameMessage[0])
    end;
  end;
  LabelAllcoatedDatagrams.Caption := 'Allocated Buffers: ' + IntToStr(InprocessMessageAllocated);
end;

procedure TForm1.FormCloseQuery(Sender: TObject; var CanClose: boolean);
begin
  CanClose := CanClose;
  CanNodeManager.Free;
  // There is a race of CloseSocket here... called twice in thread and in the CloseConnection call
  EthernetServer.CloseConnection(nil);
  EthernetServer.Free;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  EthernetServer := TLccEthernetServer.Create(nil);
  EthernetServer.Gridconnect := True;
  CanNodeManager := TLccCanNodeManager.Create(nil);
  CanNodeManager.OnLccMessageSend := @SendMessage;
  CanNodeManager.OnLccMessageReceive := @ReceiveMessage;
  EthernetServer.NodeManager := CanNodeManager;
  SynEdit1.Clear;
end;

procedure TForm1.OnEthernetConnectionChange(Sender: TObject; EthernetRec: TLccEthernetRec);
begin
  case EthernetRec.ConnectionState of
    ccsListenerConnecting:          StatusBar1.Panels[0].Text := 'Server Connecting: ' + EthernetRec.ListenerIP + ':' + IntToStr(EthernetRec.ListenerPort);
    ccsListenerConnected:           StatusBar1.Panels[0].Text := 'Server Connected: ' + EthernetRec.ListenerIP + ':' + IntToStr(EthernetRec.ListenerPort);
    ccsListenerDisconnecting:       StatusBar1.Panels[0].Text := 'Server Disconnecting: ';
    ccsListenerDisconnected:        StatusBar1.Panels[0].Text := 'Server Disconnected: ';
    ccsListenerClientConnecting:    StatusBar1.Panels[1].Text := 'Client Connecting: ' + EthernetRec.ClientIP + ':' + IntToStr(EthernetRec.ClientPort);
    ccsListenerClientConnected:     StatusBar1.Panels[1].Text := 'Client Connected: ' + EthernetRec.ClientIP + ':' + IntToStr(EthernetRec.ClientPort);
    ccsListenerClientDisconnecting: StatusBar1.Panels[1].Text := 'Client Disconnecting: ';
    ccsListenerClientDisconnected:  StatusBar1.Panels[1].Text := 'Client Disconnected: ';
  end;
end;

procedure TForm1.ReceiveMessage(Sender: TObject; LccMessage: TLccMessage);
begin
  if CheckBoxLogging.Checked then
  begin
    SynEdit1.BeginUpdate(False);
    try
      SynEdit1.Lines.Add('R: ' + GridConnectToDetailedGridConnect(LccMessage.ConvertToGridConnectStr(#13)));
      SynEdit1.EndUpdate;
    finally
    end;
  end;
end;

procedure TForm1.SendMessage(Sender: TObject; LccMessage: TLccMessage);
begin
  EthernetServer.SendMessage(LccMessage);

  if CheckBoxLogging.Checked then
  begin
    SynEdit1.BeginUpdate(False);
    try
      SynEdit1.Lines.Add('S: ' + GridConnectToDetailedGridConnect(LccMessage.ConvertToGridConnectStr(#13)));
      SynEdit1.EndUpdate;
    finally
    end;
  end;
end;

end.

