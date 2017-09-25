#include "myMessages.h"


module MQTTmoteC @safe(){
	uses {
		interface Boot;
		interface AMPacket;
		interface PacketAcknowledgements;
		interface SplitControl as AMControl;
		interface Packet;
		interface Random;
		// interface Mutex;
		// MQTT client interfaces
			interface Timer<TMilli> as ClientRoutineTimer;
			interface AMSend as CONNECTsender;
			interface AMSend as SUBSCRIBEsender;
			interface AMSend as PUBLISHsender;
			interface Receive as FORWARDreceiver;
			// represent the read from a sensor
			interface Read<uint16_t>;
		// MQTT server interfaces
			interface Timer<TMilli> as ServerForwardTimer;
			interface Receive as CONNECTreceiver;
			interface Receive as SUBSCRIBEreceiver;
			interface Receive as PUBLISHreceiver;
			interface AMSend as FORWARDsender;
	}
}

implementation{

	/////////////////////////////////////////////
	////////////// SHARED VARIABLES /////////////
	/////////////////////////////////////////////
	
	sizedArray_t connectedDevices;
	// array in position 0 contains id subscribed at qos0
	// array in position 1 contains id subscribed at qos1
	sizedArray_t TEMPsubs[2];
	sizedArray_t HUMsubs[2];
	sizedArray_t LUMINsubs[2];
	
	message_t pkt;
	message_t pkt_subscribe;
	message_t pkt_publish;
	message_t pkt_forward;
	// flags to monitor whether there is something to forward or not
	int somethingToForward;
	// flags to monitor whether something is being forwarded or not
	int lockedForwarder;
	// flags to monitor the status of the initialization
	int connected;
	int subscriptionDone;
	// topic on which publish
	int publishedTopic;
	// topic to which subscribe, and corresponding qos (MQTT-like)
	int subscription;
	int qos;
	// message to be forwarded to subscribers
	pub_msg_t* toBeForwarded;




	/////////////////////////////////////////////
	///////// HELPER FUNCTIONS and TASKS ////////
	/////////////////////////////////////////////

	task void forwardToSubscribers(){
		int i;
		forw_msg_t* myPayload;
		sizedArray_t* topicSubcribers;
		// toBeForwarded points to the message that has just been published
		// get the significant values in order not to create concurrency problems if other message are published 
		// and they need toBeForwarded variable in PUBLISHreceiver.receive
		
		myPayload = (forw_msg_t*)(call Packet.getPayload(&pkt_forward,sizeof(forw_msg_t)));
		myPayload-> topic = toBeForwarded->topic;
		myPayload-> value = toBeForwarded->value;
		switch(myPayload->topic){
			case TEMPERATURE:
				topicSubcribers = TEMPsubs;
				break;
			case HUMIDITY:
				topicSubcribers = HUMsubs;
				break;
			case LUMINOSITY:
				topicSubcribers = LUMINsubs;
				break;
			default:
				// if the topic does not exists, end the procedure immediately 
				dbg("forwardServer","error: illegal topic id %hhu\n");
				return;
		}
		// all subscribed clients, with qos=0
		dbg("forwardServer","registrati con qos 0: %hhu \n",topicSubcribers[1].counter);
		dbg("forwardServer","registrati con qos 1: %hhu \n",topicSubcribers[0].counter);
		myPayload->qos = 0;
		for(i = 0; i < topicSubcribers[0].counter;i++){
			myPayload->destID = topicSubcribers[0].IDs[i];
			dbg("forwardServer","forwardo a %hhu\n",myPayload->destID);
			call FORWARDsender.send(myPayload->destID, &pkt_forward,sizeof(forw_msg_t));
		}
		// all subscribed clients, with qos=1
		myPayload->qos = 1;
		for(i = 0; i < topicSubcribers[1].counter;i++){
			myPayload->destID = topicSubcribers[1].IDs[i];
			dbg("forwardServer","forwardo a %hhu\n",myPayload->destID);
			call PacketAcknowledgements.requestAck(&pkt_forward);
			call FORWARDsender.send(myPayload->destID, &pkt_forward,sizeof(forw_msg_t));
		}


	}

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
		if(x->counter >= MAX_CONNECTED){
			return 0;
		}
		// if the ID is already present in the array
		if(searchID(x,newID)){
			return 1;
		}
		// otherwise, append the ID
		x->IDs[x->counter] = newID;
		x->counter = x->counter+1;
		return 1;
	}

	// data structures required to implement broker functionalities
	task void initServerStructures(){
		// call Mutex.init(&forwardMessages_mutex);
		somethingToForward = 0;
		lockedForwarder = 0;

		connectedDevices.counter = 0;
		TEMPsubs[0].counter		 = 0;
		TEMPsubs[1].counter		 = 0;
		HUMsubs[0].counter		 = 0;
		HUMsubs[1].counter		 = 0;
		LUMINsubs[0].counter	 = 0;
		LUMINsubs[1].counter	 = 0;
	}

	task void sendSubscription(){
		sub_msg_t* myPayload;
		
		if (subscription == NO_SUBS){
			dbg("clientMessages","node %hhu has no subscriptions\n", TOS_NODE_ID);
			return;
		} else {
			dbg("clientMessages","Node %hhu wants topic %hhu \n",TOS_NODE_ID, subscription);
		}

		myPayload = (sub_msg_t*)(call Packet.getPayload(&pkt_subscribe,sizeof(sub_msg_t)));
		// fill the fields of the message
		myPayload-> ID = TOS_NODE_ID;
		myPayload-> subscription = subscription;
		// myPayload-> qos = (call Random.rand16() % 2);
		// test purpose
		myPayload-> qos = 0;

		call PacketAcknowledgements.requestAck(&pkt_subscribe);
		call SUBSCRIBEsender.send(1, &pkt_subscribe,sizeof(sub_msg_t));
	}

	task void initClientStructures(){	
		connected = 0;
		subscriptionDone = 0;

		// 4 because: 3 topics, or no topics
		// subscription = call Random.rand16() % 4;
		// publishedTopic = call Random.rand16() % 4;

		// for test purpose 
		subscription = 0;
		publishedTopic = 0;

	}




	/////////////////////////////////////////////
	////// CLIENT INTERFACE IMPLEMENTATION //////
	/////////////////////////////////////////////

	// this timer loops until connection is achieved
	// then, it starts the subscription procedure and ends the loop
	event void ClientRoutineTimer.fired() {
		if(connected){
			if(!subscriptionDone){
				post sendSubscription();
				subscriptionDone = 1;
			}
			else{
				// force the read procedure from the (fake) sensor
				call Read.read();
			}
		}
		// chiamo timer
		call ClientRoutineTimer.startOneShot(WAIT_CONNECT_TIME);
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

	// PUBLISHsender (AMSend) interface
	event void PUBLISHsender.sendDone(message_t* msg, error_t error){
		pub_msg_t *myPayload = (pub_msg_t*)(call Packet.getPayload(msg,sizeof(pub_msg_t)));
		if(/*&pkt_publish == buf && */ error == SUCCESS ){ 
			dbg("clientMessages", "PUBLISH correctly sent...\n");
			if(myPayload->qos == 0){
				dbg("clientMessages","No ack requested\n");
				return;
			}
			if(call PacketAcknowledgements.wasAcked(msg)){
				dbg("clientMessages", "PUBLISH acked \n");
			}
			else{
				dbg("clientMessages", "PUBLISH non acked \n");
				call PacketAcknowledgements.requestAck(&pkt_publish);
				call PUBLISHsender.send(1, &pkt_publish,sizeof(pub_msg_t));
			}
		}
	}

	// fires when a new data is read from the (fake) sensor
	event void Read.readDone(error_t result, uint16_t data) {
		pub_msg_t* myPayload;

		dbg("clientMessages","data from sensor %hhu \n",data);
		if(subscriptionDone){
			myPayload = (pub_msg_t*)(call Packet.getPayload(&pkt_publish,sizeof(pub_msg_t)));
			// fill the msg fields
			myPayload->topic = publishedTopic;
			myPayload->value = data;
			// myPayload->qos = (call Random.rand16() % 2);
			myPayload->qos = 1;

			// qos management, compliant to the requirements
			if(myPayload->qos == 1){
				call PacketAcknowledgements.requestAck(&pkt_publish);
				dbg("clientMessages","qos in PUBLISH = 1\n");
			}
			call PUBLISHsender.send(1, &pkt_publish,sizeof(pub_msg_t));
		}
	}

	// CONNECTreceiver interface
	event message_t* FORWARDreceiver.receive(message_t* bufPtr, void* payload, uint8_t len){
		forw_msg_t* myPayload;
		myPayload = (forw_msg_t*)payload;
		
		dbg("forwardClient","topic %hhu, value %hhu",myPayload->topic, myPayload->value);
		return bufPtr;
	}




	/////////////////////////////////////////////
	////// SERVER INTERFACE IMPLEMENTATION //////
	/////////////////////////////////////////////

	// FORWARD
	event void FORWARDsender.sendDone(message_t* msg, error_t error){
		forw_msg_t* myPayload;
		myPayload = (forw_msg_t*)call Packet.getPayload(msg,sizeof(forw_msg_t));

		if (myPayload->qos == 1){
			if(/*&pkt_subscribe == buf && */ error == SUCCESS ){ 
				dbg("clientMessages", "FORWARD correctly sent...\n");
				if(call PacketAcknowledgements.wasAcked(msg)){
					dbg("clientMessages", "FORWARD acked \n");
				}
				else{
					dbg("clientMessages", "FORWARD non acked \n");
					call PacketAcknowledgements.requestAck(&pkt_forward);
					call FORWARDsender.send(myPayload->destID, &pkt_forward,sizeof(forw_msg_t));
				}
			}
		}
		return;
	}


	// CONNECTreceiver interface
	event message_t* CONNECTreceiver.receive(message_t* bufPtr, void* payload, uint8_t len){
		connect_msg_t* myPayload;
		myPayload = (connect_msg_t*)payload;
		
		if(addID(&connectedDevices,myPayload->ID) == 1)
			dbg("serverMessages","Device %hu connected\n",myPayload->ID);
		else
			dbg("serverMessages","Device %hu can't connect, too many devices already connected\n",myPayload->ID);
		return bufPtr;
	}



	// SUBSCRIBEreceiver interface
	event message_t* SUBSCRIBEreceiver.receive(message_t* bufPtr, void* payload, uint8_t len){
		sub_msg_t* myPayload;
		sizedArray_t* topicSubcribers;
		int err; 

		myPayload = (sub_msg_t*)payload;
		if((myPayload->qos != 0) && (myPayload->qos =! 1)){
			dbg("serverMessages","Subscription rejected: incorrect qos value\n");
			return bufPtr;
		}
		switch(myPayload->subscription){
			case TEMPERATURE:
				topicSubcribers = &TEMPsubs[myPayload->qos];
				break;
			case HUMIDITY:
				topicSubcribers = &HUMsubs[myPayload->qos];
				break;
			case LUMINOSITY:
				topicSubcribers = &LUMINsubs[myPayload->qos];
				break;
			default:
				topicSubcribers = NULL;
		}
		
		if(topicSubcribers == NULL){
			dbg("serverMessages","Subscription rejected: incorrect topic id\n");
		} 
		else {
			// device is not among the connected ones
			if(!searchID(&connectedDevices,myPayload->ID)){
				dbg("serverMessages","Subscription rejected: unknown device ID\n");
			}
			// add the ID to the subscriber to the topic
			else {
				err = addID(topicSubcribers,myPayload->ID);
				if(err == 0)
					dbg("serverMessages","Subscription rejected: max number of devices exceeded\n");
				else
					dbg("serverMessages","Subscription accepted:\n \t\tmote %hhu subscribed to %hhu, qos:%hhu\n",myPayload->ID,myPayload->subscription,myPayload->qos);
			}
		}
		return bufPtr;
	}

	event void ServerForwardTimer.fired(){
		// using a task here, because this is likely to be 
		// the most expensive operation 
		if(somethingToForward){
			lockedForwarder = 1;
			post forwardToSubscribers();
			somethingToForward = 0;
			lockedForwarder = 0;
		}
	}
	
	event message_t* PUBLISHreceiver.receive(message_t* bufPtr, void* payload, uint8_t len){
		dbg("publishServer","ricevuto coso\n");
		// use this flag to check if another message is being forwarded
		// is this is the case, do not modify toBeForwarded because it's being used by forwardToSubscribers task
		if(!lockedForwarder){
			toBeForwarded = (pub_msg_t*) payload;
			somethingToForward = 1;
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
			connect_msg_t* myPayload;
			myPayload = (connect_msg_t*)(call Packet.getPayload(&pkt,sizeof(connect_msg_t)));
			// put device ID as payload
			myPayload-> ID = TOS_NODE_ID;
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
			post initClientStructures();
			call ClientRoutineTimer.startOneShot(WAIT_CONNECT_TIME);
		}
		else{ 
			dbg("boot","MQTTserver on\n");
			post initServerStructures();
			call ServerForwardTimer.startPeriodic(CHECK_FORWARD_PERIODICITY);
		}
	}

}