#include "myMessages.h"

module MQTTmoteC @safe(){
	uses {
		interface Boot;
		interface SplitControl as AMControl;
		interface Timer<TMilli> as MessageTimer;
		interface Packet;
		// only for MQTT clients
		interface AMSend as ValueSender;
		// only for MQTT server
		interface Receive as ReceiveValues;
	}
}

implementation{
	// shared variables
	message_t packet;
	send_value_msg_t* my_payload;

	/////////////////////////////////////////////
	////// CLIENT INTERFACE IMPLEMENTATION //////
	/////////////////////////////////////////////
	
	// ValueSender (AMSend) interface
	event void ValueSender.sendDone(message_t* msg, error_t error){
		dbg("clientMessages", "message sent\n");
	}

	// MessageTimer (Timer) interface
	event void MessageTimer.fired(){
		my_payload = (send_value_msg_t*)call Packet.getPayload(&packet, sizeof(send_value_msg_t));
		my_payload-> msg_value = 56;
		call ValueSender.send(1, &packet, sizeof(send_value_msg_t));
	}

	/////////////////////////////////////////////
	////// SERVER INTERFACE IMPLEMENTATION //////
	/////////////////////////////////////////////

	// ReceiveValues interface
	event message_t* ReceiveValues.receive(message_t* msgPtr, void* payload, uint8_t len){
		my_payload = (send_value_msg_t*)payload;
		dbg("serverMessages","PacketReceived, value: %hu\n",my_payload->msg_value);
		return msgPtr;
	}
	
	/////////////////////////////////////////////
	////// SHARED INTERFACE IMPLEMENTATION //////
	/////////////////////////////////////////////

	// SplitControl as AMControl interface
	event void AMControl.startDone(error_t error){
		if(error == SUCCESS)
			dbg("AMcontrol", "AM started\n");
		else
			call AMControl.start();
	}
	event void AMControl.stopDone(error_t error){
		dbg("AMcontrol", "AM stopped\n");
	}

	// Boot interface
	event void Boot.booted(){
		call AMControl.start();
		if (TOS_NODE_ID != 1){
			call MessageTimer.startPeriodic(1000);
			dbg("boot","MQTTclient on\n");
		}
		else 
			dbg("boot","MQTTserver on\n");
	}

}