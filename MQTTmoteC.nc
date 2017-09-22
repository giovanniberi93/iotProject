#include "myMessages.h"

module MQTTmoteC @safe(){
	uses {
		interface Boot;
		interface AMPacket;
		interface PacketAcknowledgements;
		interface SplitControl as AMControl;
		interface Packet;
		interface Random;
		interface Timer<TMilli> as MilliTimer;
		// MQTT client interfaces
		interface AMSend as CONNECTsender;
		interface AMSend as SUBSCRIBEsender;
		// MQTT server interfaces
		interface Receive as CONNECTreceiver;
		interface Receive as SUBSCRIBEreceiver;
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
	message_t pkt_subscribe;
	// flags to monitor the status of the initialization
	int connected;
	int chooseSubscription;
	// topic to which subscribe, and corresponding qos (MQTT-like)
	int subscription;
	int qos;
	/////////////////////////////////////////////
	///////// HELPER FUNCTIONS and TASKS ////////
	/////////////////////////////////////////////

	bool isClient(){
		return (TOS_NODE_ID != 1);
	}

	int searchID(sizedArray_t* x, nx_int16_t searchedID){
		int i;
		for (i=0; i < x->counter; i++)
			if (x->IDs[i] == searchedID)
				return 1;
		return 0;
	}

	// given an ID and a sized array, it checks if the id is already into the list.
	// If it is not, the ID is added to the sized array, otherwise return
	int addID(sizedArray_t* x, nx_int16_t newID){
		if(x->counter >= MAX_CONNECTED)
			return 0;
		// if the ID is already present in the array
		if(searchID(x,newID))
			return 1;
		// otherwise, append the ID
		x->IDs[x->counter] = newID;
		x->counter = x->counter+1;
		return 1;
	}

	// data structures required to implement broker functionalities
	task void initServerStructures(){
		connectedDevices.counter = 0;
		TEMPsubs.counter = 0;
		HUMsubs.counter = 0;
		LUMINsubs.counter = 0;
	}

	task void sendSubscription(){
		sub_msg_t* my_payload;
		
		// 4 because: 3 topics, or no topics
		subscription = call Random.rand16() % 4;

		// for test 
		// subscription = 0;
		if (subscription == NO_SUBS){
			dbg("clientMessages","node %hhu has no subscriptions", TOS_NODE_ID);
			return;
		} else {
			dbg("clientMessages","Node %hhu wants topic %hhu \n",TOS_NODE_ID, subscription);
		}

		my_payload = (sub_msg_t*)(call Packet.getPayload(&pkt_subscribe,sizeof(sub_msg_t)));
		// fill the fields of the message
		my_payload-> ID = TOS_NODE_ID;
		my_payload-> subscription = subscription;
		my_payload-> qos = (call Random.rand16() % 2);

		call PacketAcknowledgements.requestAck(&pkt_subscribe);
		call SUBSCRIBEsender.send(1, &pkt_subscribe,sizeof(sub_msg_t));
	}

	void initClientStructures(){	
		connected = 0;
		chooseSubscription = 0;
		// subscription = NO_SUBS;
	}


	/////////////////////////////////////////////
	////// CLIENT INTERFACE IMPLEMENTATION //////
	/////////////////////////////////////////////
	
	event void MilliTimer.fired() {
		if(connected){
			if(!chooseSubscription){
				chooseSubscription = 1;
				post sendSubscription();
				// call CONNECTsender.send(AM_BROADCAST_ADDR, &pkt_subscribe,sizeof(sub_msg_t));
			}
			else{
				// TODO
			}
		}
		call MilliTimer.startOneShot(call Random.rand16() % MAX_INTERVAL_CLIENT);
	}

	// CONNECTsender (AMSend) interface
	event void CONNECTsender.sendDone(message_t* msg, error_t error){
		if(/*&pkt_subscribe == buf && */ error == SUCCESS ){ 
			dbg("clientMessages", "CONNECT correctly sent...\n");
			if(call PacketAcknowledgements.wasAcked(msg)){
				connected = 1;
				dbg("clientMessages", "CONNECT acked \n");
			}
			else{
				dbg("clientMessages", "CONNECT non acked \n");
				call PacketAcknowledgements.requestAck(&pkt);
				call CONNECTsender.send(1, &pkt,sizeof(connect_msg_t));
			}
		}
	}

	// SUBSCRIBEsender (AMSend) interface
	event void SUBSCRIBEsender.sendDone(message_t* msg, error_t error){
		if(/*&pkt_subscribe == buf && */ error == SUCCESS ){ 
			dbg("clientMessages", "SUBSCRIBE correctly sent...\n");
			if(call PacketAcknowledgements.wasAcked(msg)){
				dbg("clientMessages", "SUBSCRIBE acked \n");
			}
			else{
				dbg("clientMessages", "SUBSCRIBE non acked \n");
				call PacketAcknowledgements.requestAck(&pkt_subscribe);
				call SUBSCRIBEsender.send(1, &pkt_subscribe,sizeof(sub_msg_t));
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
		return bufPtr;
	}

	// SUBSCRIBEreceiver interface
	event message_t* SUBSCRIBEreceiver.receive(message_t* bufPtr, void* payload, uint8_t len){
		sub_msg_t* my_payload;
		sizedArray_t* topicSubcribers;
		int err; 

		my_payload = (sub_msg_t*)payload;
		switch(my_payload->subscription){
			case TEMPERATURE:
				topicSubcribers = &TEMPsubs;
				break;
			case HUMIDITY:
				topicSubcribers = &HUMsubs;
				break;
			case LUMINOSITY:
				topicSubcribers = &LUMINsubs;
				break;
			default:
				topicSubcribers = NULL;
		}
		if(topicSubcribers == NULL){
			dbg("serverMessages","Subscription rejected: incorrect topic id\n");
		} 
		else {
			// device is not among the connected ones
			if(!searchID(&connectedDevices,my_payload->ID)){
				dbg("serverMessages","Subscription rejected: unknown device ID\n");
			}
			// add the ID to the subscriber to the topic
			else {
				err = addID(topicSubcribers,my_payload->ID);
				if(err == 0)
					dbg("serverMessages","Subscription rejected: max number of devices exceeded\n");
				else
					dbg("serverMessages","Subscription accepted:\n \t\tmote %hhu subscribed to %hhu \n",my_payload->ID,my_payload->subscription);
			}
		}
		return bufPtr;
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
			dbg("clientMessages","sono client");
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
			// sync call, to be sure all values are set
			// call SUBSCRIBEsender.send(1, &pkt_subscribe,sizeof(sub_msg_t));
			// dbg("boot","mandato un coso\n");
			initClientStructures();
			call MilliTimer.startOneShot(call Random.rand16() % MAX_INTERVAL_CLIENT);
		}
		else{ 
			dbg("boot","MQTTserver on\n");
			post initServerStructures();
		}
	}

}