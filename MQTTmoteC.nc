#include "myMessages.h"

module MQTTmoteC @safe(){
	uses {
		interface Boot;
		interface AMPacket;
		interface PacketAcknowledgements;
		interface SplitControl as AMControl;
		interface Packet;
		// MQTT client interfaces
		interface AMSend as CONNECTsender;
		// MQTT server interfaces
		interface Receive as CONNECTreceiver;
	}
}

implementation{

	/////////////////////////////////////////////
	////////////// SHARED VARIABLES /////////////
	/////////////////////////////////////////////
	
	sizedArray_t connectedDevices;
	sizedArray_t TEMPsubs;
	sizedArray_t HUMsubs;
	sizedArray_t LUMINsubs;
	
	message_t pkt;
	/////////////////////////////////////////////
	///////// HELPER FUNCTIONS and TASKS ////////
	/////////////////////////////////////////////

	bool isClient(){
		return (TOS_NODE_ID != 1);
	}

	// given an ID and a sized array, it checks if the id is already into the list.
	// If it is not, the ID is added to the sized array, otherwise return
	int addID(sizedArray_t* x, nx_int16_t newID){
		int i;
		if((int)x->counter >= (int)MAX_CONNECTED)
			return 0;
		for (i=0; i < x->counter; i++)
			if (x->IDs[i] == newID)
				return 1;
		x->IDs[x->counter] = newID;
		x->counter = x->counter+1;
		return 1;
	}

	// data structures required to implement broker functionalities
	task void initBrokerStructures(){
		connectedDevices.counter = 0;
		TEMPsubs.counter = 0;
		HUMsubs.counter = 0;
		LUMINsubs.counter = 0;
	}

	/////////////////////////////////////////////
	////// CLIENT INTERFACE IMPLEMENTATION //////
	/////////////////////////////////////////////
	
	// CONNECTsender (AMSend) interface
	event void CONNECTsender.sendDone(message_t* msg, error_t error){
		if(/*&packet == buf && */ error == SUCCESS ){ 
			dbg("clientMessages", "Packet correctly sent...");
			if(call PacketAcknowledgements.wasAcked(msg)){
				dbg("clientMessages", "acked \n");
			}
			else{
				dbg("clientMessages", "NON acked \n");
				call PacketAcknowledgements.requestAck(&pkt);
				call CONNECTsender.send(1, &pkt,sizeof(connect_msg_t));
			}
		}

	}

	/////////////////////////////////////////////
	////// SERVER INTERFACE IMPLEMENTATION //////
	/////////////////////////////////////////////

	// CONNECTreceiver interface
	event message_t* CONNECTreceiver.receive(message_t* bufPtr, void* payload, uint8_t len){
		connect_msg_t* my_payload;
		my_payload = (connect_msg_t*)payload;
		
		if(addID(&connectedDevices,my_payload->ID) == 1)
			dbg("serverMessages","Device %hu connected\n",my_payload->ID);
		else
			dbg("serverMessages","Device %hu can't connect, too many devices already connected\n",my_payload->ID);
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

		// client connects to the server
		if(isClient()){
			connect_msg_t* my_payload;
			my_payload = (connect_msg_t*)(call Packet.getPayload(&pkt,sizeof(connect_msg_t)));
			// put device ID as payload
			my_payload-> ID = TOS_NODE_ID;
			call PacketAcknowledgements.requestAck(&pkt);
			call CONNECTsender.send(1, &pkt,sizeof(connect_msg_t));

		}
	}
	event void AMControl.stopDone(error_t error){
		dbg("AMcontrol", "AM stopped\n");
	}

	// Boot interface
	event void Boot.booted(){
		call AMControl.start();
		if (isClient()){
			dbg("boot","MQTTclient on\n");
		}
		else{ 
			dbg("boot","MQTTserver on\n");
			post initBrokerStructures();
		}
	}

}