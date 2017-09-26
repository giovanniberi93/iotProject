#include "MQTT.h"

configuration MQTTmoteAppC{}

implementation{
	components MQTTmoteC as App, MainC; 
	components ActiveMessageC;
	components RandomC;

	// generic components:
		components new TimerMilliC() as ClientTimer;
		components new TimerMilliC() as ServerTimer;
		components new FakeSensorC();
		// CONNECT
		components new AMSenderC(CONNECT) 	as CONNECTsender;
		components new AMReceiverC(CONNECT) as CONNECTreceiver;
		// SUBSCRIBE
		components new AMSenderC(SUBSCRIBE) 	as SUBSCRIBEsender;
		components new AMReceiverC(SUBSCRIBE) 	as SUBSCRIBEreceiver;
		// PUBLISH
		components new AMSenderC(PUBLISH) 	as PUBLISHsender;
		components new AMReceiverC(PUBLISH) as PUBLISHreceiver;
		// forward messages
		components new AMSenderC(FORWARD) 	as FORWARDsender;
		components new AMReceiverC(FORWARD) as FORWARDreceiver;

	// App.interface	-> Component that offers that interface
	// Shared components
	App.Boot			-> MainC.Boot;
	App.AMControl		-> ActiveMessageC;
	App.Packet			-> CONNECTreceiver;
	App.AMPacket		-> CONNECTreceiver;
	App.Random			-> RandomC;
	App.PacketAcknowledgements -> ActiveMessageC;
	App.Seed 			-> RandomC;
	// Client-only components
	App.CONNECTsender		-> CONNECTsender;
	App.SUBSCRIBEsender		-> SUBSCRIBEsender;
	App.PUBLISHsender		-> PUBLISHsender;
	App.FORWARDreceiver		-> FORWARDreceiver;
	App.Read 				-> FakeSensorC;
	App.ClientRoutineTimer	-> ClientTimer;
	// Server-only components
	App.CONNECTreceiver		-> CONNECTreceiver;
	App.SUBSCRIBEreceiver	-> SUBSCRIBEreceiver;
	App.PUBLISHreceiver		-> PUBLISHreceiver;
	App.FORWARDsender		-> FORWARDsender;
	App.ServerForwardTimer	-> ServerTimer;
}