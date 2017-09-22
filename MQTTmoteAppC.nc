#include "myMessages.h"

configuration MQTTmoteAppC{}

implementation{
	components MQTTmoteC as App, MainC; 
	components ActiveMessageC;
	components RandomC;

	// generic components:
		components new TimerMilliC();
		// CONNECT
		components new AMSenderC(CONNECT) as CONNECTsender;
		components new AMReceiverC(CONNECT) as CONNECTreceiver;
		// SUBSCRIBE
		components new AMSenderC(SUBSCRIBE) as SUBSCRIBEsender;
		components new AMReceiverC(SUBSCRIBE) as SUBSCRIBEreceiver;

	// App.interface	-> Component that offers that interface
	// Shared components
	App.Boot			-> MainC.Boot;
	App.AMControl		-> ActiveMessageC;
	App.Packet			-> CONNECTreceiver;
	App.AMPacket		-> CONNECTreceiver;
	App.Random			-> RandomC;
	App.MilliTimer		-> TimerMilliC;
	App.PacketAcknowledgements -> ActiveMessageC;
	// Client-only components
	App.CONNECTsender	-> CONNECTsender;
	App.SUBSCRIBEsender	-> SUBSCRIBEsender;
	// Server-only components
	App.CONNECTreceiver		-> CONNECTreceiver;
	App.SUBSCRIBEreceiver	-> SUBSCRIBEreceiver;
}