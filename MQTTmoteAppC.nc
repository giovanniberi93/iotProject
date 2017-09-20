#include "myMessages.h"

configuration MQTTmoteAppC{}

implementation{
	components MQTTmoteC as App, MainC; 
	components ActiveMessageC;
	// generic components
	components new AMSenderC(CONNECT) as CONNECTsender;
	components new AMReceiverC(CONNECT) as CONNECTreceiver;
	components new TimerMilliC();

	// App.interface	-> Component that offers that interface
	// Shared components
	App.Boot			-> MainC.Boot;
	App.AMControl		-> ActiveMessageC;
	App.Packet			-> CONNECTreceiver;
	App.AMPacket		-> CONNECTreceiver;
	// Client-only components
	App.MessageTimer	-> TimerMilliC;
	App.CONNECTsender	-> CONNECTsender;
	// Server-only components
	App.CONNECTreceiver	-> CONNECTreceiver;
}