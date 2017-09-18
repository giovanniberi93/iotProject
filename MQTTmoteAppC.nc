#include "myMessages.h"

configuration MQTTmoteAppC{}

implementation{
	components MQTTmoteC as App, MainC; 
	components ActiveMessageC;
	// generic components
	components new AMSenderC(SEND_VALUE_MSG);
	components new AMReceiverC(SEND_VALUE_MSG);
	components new TimerMilliC();

//  App.interface		-> Component that offers that interface
	// Shared components
	App.Boot			-> MainC.Boot;
	App.AMCo
	ntrol		-> ActiveMessageC;
	App.Packet			-> AMSenderC;
	// Client-only components
	App.ValueSender		-> AMSenderC;
	App.MessageTimer	-> TimerMilliC;
	// Server-only components
	App.ReceiveValues	-> AMReceiverC;
}