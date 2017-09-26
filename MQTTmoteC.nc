#include "MQTT.h"

module MQTTmoteC @safe(){
	uses {
		interface ParameterInit<uint16_t> as Seed;
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
	// topicSubscriptions[i] = 1 --> interested in topic i
	// topicSubscriptions[i] = 0 --> NOT interested in topic i
	int topicSubscriptions[3];
	int subscriptionsqos[3];
	// message to be forwarded to subscribers
	pub_msg_t* toBeForwarded;
	// ids of last received msg ids; only for forward and publish message, because the other ones are idempotent
	nx_int16_t lastPublishID;
		// used by the server; requires one lastID for each client, because their IDs are independent
	nx_int16_t lastPublishIDfromClients[MAX_CONNECTED];
	nx_int16_t lastForwardID;



	/////////////////////////////////////////////
	////////////// HELPER FUNCTIONS  ////////////
	/////////////////////////////////////////////

	// return ID of the next address in the order of the list of subscribers
	// return -1 if there are no address with the required qos to which forward the message 
	int getNextID(int currentDestination, int topicID, int searchedQos){
		sizedArray_t* topicSubcribers;
		int i;

		switch(topicID){
			case TEMPERATURE:
				topicSubcribers = &TEMPsubs[searchedQos];
				break;
			case HUMIDITY:
				topicSubcribers = &HUMsubs[searchedQos];
				break;
			case LUMINOSITY:
				topicSubcribers = &LUMINsubs[searchedQos];
				break;
			default:
				// if the topic does not exists, end the procedure immediately 
				dbg("FORWARDserver","error: illegal topic id %hhu\n", topicID);
				return -1;
		}
		
		// dbg("FORWARDserver","counter dell'array selezionato %hhu\n", topicSubcribers->counter);
		// dbg("FORWARDserver","currentDestination è %hhu\n", currentDestination);
		for(i = 0; i < topicSubcribers->counter; i++){
			// i find currentDestination, that is not in the last position
			if((topicSubcribers->IDs[i] == currentDestination) && (i != topicSubcribers->counter - 1))
				return topicSubcribers->IDs[i+1];
		}
		return -1;
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

	// return the pointer to a sizedArray containing the subscribers to a topic, with given qos
	sizedArray_t* getTopicSubscribers(int topicID, int qos){
		switch(topicID){
			case TEMPERATURE:
				return &TEMPsubs[qos];
			case HUMIDITY:
				return &HUMsubs[qos];
			case LUMINOSITY:
				return &LUMINsubs[qos];
			default:
				return NULL;
				dbg("SUBSCRIBEserver","Subscription rejected: incorrect topic id\n");
		}
	}	





	/////////////////////////////////////////////
	//////////////////// TASKS //////////////////
	/////////////////////////////////////////////

	// init random seed
	task void initRNGseed(){
	    uint16_t seed;
	    FILE *f;
	    f = fopen("/dev/urandom", "r");
	    fread(&seed, sizeof(seed), 1, f);
	    fclose(f);
	    call Seed.init(seed+TOS_NODE_ID+1);
	}


	task void forwardToSubscribers(){
		forw_msg_t* myPayload;
		sizedArray_t* topicSubcribers;
		// toBeForwarded points to the message that has just been published
		// get the significant values in order not to create concurrency problems if other message are published 
		// and they need toBeForwarded variable in PUBLISHreceiver.receive
		dbg("FORWARDserver","New packet to forward on topic %hhu, value: %hhu\n", toBeForwarded->topic, toBeForwarded->value);
		myPayload = (forw_msg_t*)(call Packet.getPayload(&pkt_forward,sizeof(forw_msg_t)));
		myPayload-> sourceID = toBeForwarded->sourceID;
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
				dbg("FORWARDserver","error: illegal topic id %hhu\n", myPayload->topic);
				return;
		}
		myPayload->msgID = lastForwardID;
		// if I have at least one subscribed with qos = 0 
		if(topicSubcribers[0].counter > 0){
			myPayload->qos = 0;
			myPayload->destID = topicSubcribers[0].IDs[0];
			call FORWARDsender.send(myPayload->destID, &pkt_forward,sizeof(forw_msg_t));
			lastForwardID++;
		} else if (topicSubcribers[1].counter > 0){
			// if I do not have subscribers with qos = 0, but at least one with qos = 1 
			myPayload->qos = 1;
			myPayload->destID = topicSubcribers[1].IDs[0];
			call PacketAcknowledgements.requestAck(&pkt_forward);
			call FORWARDsender.send(myPayload->destID, &pkt_forward,sizeof(forw_msg_t));
			lastForwardID++;
		} else {
			// there are no subscribers at all
			lockedForwarder = 0;
		}
	}


	task void sendSubscription(){
		sub_msg_t* myPayload;
		nx_int16_t i;
		
		myPayload = (sub_msg_t*)(call Packet.getPayload(&pkt_subscribe,sizeof(sub_msg_t)));
		// fill the fields of the message
		myPayload-> ID = TOS_NODE_ID;
		for(i=0; i<3; i++){
			myPayload-> subscription[i] = topicSubscriptions[i];
			myPayload-> qos[i] = subscriptionsqos[i];
		}

		call PacketAcknowledgements.requestAck(&pkt_subscribe);
		call SUBSCRIBEsender.send(1, &pkt_subscribe,sizeof(sub_msg_t));
	}



	task void initClientStructures(){	
		nx_int16_t i;

		post initRNGseed();
		lastPublishID = 0;
		lastForwardID = -1;
		connected = 0;
		subscriptionDone = 0;
		// select topic to which subscribe, and on which publish;
		// set fixed subscriptions for test purpose
		// if you want a different test criteria set random subscription with: 
		// call Random.rand16()%desired_max_value
		switch(TOS_NODE_ID){
			case 2:
				topicSubscriptions[0] = 1; subscriptionsqos[0] = 0;
				topicSubscriptions[1] = 1; subscriptionsqos[1] = 1;
				topicSubscriptions[2] = 0; subscriptionsqos[2] = 0;
				publishedTopic = 0;
				break;
			case 3:
				topicSubscriptions[0] = 1; subscriptionsqos[0] = 0;
				topicSubscriptions[1] = 1; subscriptionsqos[1] = 1;
				topicSubscriptions[2] = 1; subscriptionsqos[2] = 1;
				publishedTopic = 1;
				break;
			case 4:
				topicSubscriptions[0] = 1; subscriptionsqos[0] = 0;
				topicSubscriptions[1] = 0; subscriptionsqos[1] = 0;
				topicSubscriptions[2] = 1; subscriptionsqos[2] = 0;
				publishedTopic = 2;
				break;
			default:
				dbg("SUBSCRIBEclient","error, unexpected node ID value");
				break;
		}

		dbg("SUBSCRIBEclient","Publish on %hhu and subscribes to ",publishedTopic);
		for(i=0; i<3; i++)
			if(topicSubscriptions[i] == 1)
				dbg_clear("SUBSCRIBEclient","%hhu(%hhu) ",i,subscriptionsqos[i]);
		dbg_clear("SUBSCRIBEclient","\n");

	}


	// data structures required to implement broker functionalities
	task void initServerStructures(){
		nx_int16_t i;

		somethingToForward = 0;
		lockedForwarder = 0;
		// used to check for duplicate messages
		lastForwardID = 0;
		for(i = 0; i < MAX_CONNECTED; i++)
			lastPublishIDfromClients[i] = -1;

		connectedDevices.counter = 0;
		TEMPsubs[0].counter		 = 0;
		TEMPsubs[1].counter		 = 0;
		HUMsubs[0].counter		 = 0;
		HUMsubs[1].counter		 = 0;
		LUMINsubs[0].counter	 = 0;
		LUMINsubs[1].counter	 = 0;
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
			}else{
				// force the read procedure from the (fake) sensor
				call Read.read();
			}
		}
		// chiamo timer
		call ClientRoutineTimer.startOneShot(CLIENT_AVG_SENSE_PERIOD/2 + (call Random.rand16()%CLIENT_AVG_SENSE_PERIOD));
	}

	// CONNECTsender (AMSend) interface
	event void CONNECTsender.sendDone(message_t* msg, error_t error){
		if(/*&pkt_subscribe == buf && */ error == SUCCESS ){ 
			dbg("CONNECTclient", "CONNECT correctly sent... ");
			if(call PacketAcknowledgements.wasAcked(msg)){
				connected = 1;
				dbg_clear("CONNECTclient", "and acked \n");
			}
			else{
				dbg_clear("CONNECTclient", "but NON acked \n");
				call PacketAcknowledgements.requestAck(&pkt);
				call CONNECTsender.send(1, &pkt,sizeof(connect_msg_t));
			}
		}
	}

	// SUBSCRIBEsender (AMSend) interface
	event void SUBSCRIBEsender.sendDone(message_t* msg, error_t error){
		if(/*&pkt_subscribe == buf && */ error == SUCCESS ){ 
			dbg("SUBSCRIBEclient", "SUBSCRIBE correctly sent... ");
			if(call PacketAcknowledgements.wasAcked(msg)){
				dbg_clear("SUBSCRIBEclient", "and acked \n");
				subscriptionDone = 1;
			}
			else{
				dbg_clear("SUBSCRIBEclient", "but non acked \n");
				call PacketAcknowledgements.requestAck(&pkt_subscribe);
				call SUBSCRIBEsender.send(1, &pkt_subscribe,sizeof(sub_msg_t));
			}
		}
	}

	// PUBLISHsender (AMSend) interface
	event void PUBLISHsender.sendDone(message_t* msg, error_t error){
		pub_msg_t *myPayload = (pub_msg_t*)(call Packet.getPayload(msg,sizeof(pub_msg_t)));
		if(/*&pkt_publish == buf && */ error == SUCCESS ){ 
			dbg("PUBLISHclient", "PUBLISH correctly sent... ");
			if(myPayload->qos == 0){
				dbg_clear("PUBLISHclient","no ack requested\n");
				return;
			}
			if(call PacketAcknowledgements.wasAcked(msg)){
				dbg_clear("PUBLISHclient", "and acked \n");
			}
			else{
				dbg_clear("PUBLISHclient", "non acked \n");
				call PacketAcknowledgements.requestAck(&pkt_publish);
				call PUBLISHsender.send(1, &pkt_publish,sizeof(pub_msg_t));
			}
		}
	}

	// fires when a new data is read from the (fake) sensor
	event void Read.readDone(error_t result, uint16_t data) {
		pub_msg_t* myPayload;

		dbg("PUBLISHclient","New measurement from sensor on topic %hhu, value: %hhu \n",publishedTopic,data);
		if(subscriptionDone){
			myPayload = (pub_msg_t*)(call Packet.getPayload(&pkt_publish,sizeof(pub_msg_t)));
			// fill the msg fields
			myPayload->sourceID = TOS_NODE_ID;
			myPayload->topic = publishedTopic;
			myPayload->value = data;
			myPayload->qos = 1;
			myPayload->msgID = lastPublishID;
			// increment the ID
			lastPublishID++;

			// qos management, compliant to the requirements
			if(myPayload->qos == 1){
				call PacketAcknowledgements.requestAck(&pkt_publish);
			}
			call PUBLISHsender.send(1, &pkt_publish,sizeof(pub_msg_t));
		}
	}

	// FORWARDreceiver interface
	event message_t* FORWARDreceiver.receive(message_t* bufPtr, void* payload, uint8_t len){
		forw_msg_t* myPayload;

		myPayload = (forw_msg_t*)payload;
		// only check if this message is equal to the last one; it happens if the ack was lost
		if(lastForwardID == myPayload->msgID){
			dbg("FORWARDserver","FW:Message received twice, discard\n");
			return bufPtr;
		}
		// else update id of last received msg
		else{
			lastForwardID = myPayload->msgID;
		}
		if(myPayload->sourceID == TOS_NODE_ID){
			dbg("FORWARDclient","Discard message generated from me\n");
		}
		else {
			dbg("FORWARDclient","Packet received on topic %hhu, value: %hhu\n",myPayload->topic,myPayload->value);
		}
		return bufPtr;
	}




	/////////////////////////////////////////////
	////// SERVER INTERFACE IMPLEMENTATION //////
	/////////////////////////////////////////////

	// FORWARDsender(AMsend) interface
	event void FORWARDsender.sendDone(message_t* msg, error_t error){
		long nextID;
		forw_msg_t* myPayload;

		myPayload = (forw_msg_t*)call Packet.getPayload(msg,sizeof(forw_msg_t));
		if (myPayload->qos == 1){
			if(/*&pkt_subscribe == buf && */ error == SUCCESS ){ 
				dbg("FORWARDserver", "FORWARD correctly sent... ");
				if(call PacketAcknowledgements.wasAcked(msg)){
					dbg_clear("FORWARDserver", "and acked \n");
				}
				else{
					dbg_clear("FORWARDserver", "but non acked \n");
					call PacketAcknowledgements.requestAck(&pkt_forward);
					call FORWARDsender.send(myPayload->destID, &pkt_forward,sizeof(forw_msg_t));
					return;
				}
			}
		}
		nextID = getNextID(myPayload->destID,myPayload->topic,myPayload->qos);
		if (nextID < 0){
			if(myPayload-> qos == 0){
				myPayload-> qos = 1;
				// search in the array of the subscribers with qos = 1
				nextID = getNextID(myPayload->destID,myPayload->topic,myPayload->qos);
			}
			if (nextID < 0){
				// forwarding procedure has ended
				// unlock the forwarder for new messages
				dbg_clear("FORWARDserver", "****** %d \n",nextID);
				lockedForwarder = 0;
				return;
			}
		}
		// if I get here, I have at least one node to which forward the message
		// if required, set the ack request. In every case, send the message
		if(myPayload-> qos == 1)
			call PacketAcknowledgements.requestAck(&pkt_forward);
		myPayload-> destID = nextID;
		// dbg("FORWARDserver", "FORWARD to %hhu \n", nextID);
		call FORWARDsender.send(nextID, &pkt_forward,sizeof(forw_msg_t));


		return;
	}


	// CONNECTreceiver interface
	event message_t* CONNECTreceiver.receive(message_t* bufPtr, void* payload, uint8_t len){
		connect_msg_t* myPayload;
		myPayload = (connect_msg_t*)payload;
		
		if(addID(&connectedDevices,myPayload->ID) == 1)
			dbg("CONNECTserver","Device %hu connected\n",myPayload->ID);
		else
			dbg("CONNECTserver","Device %hu can't connect, too many devices already connected\n",myPayload->ID);
		return bufPtr;
	}



	// SUBSCRIBEreceiver interface
	event message_t* SUBSCRIBEreceiver.receive(message_t* bufPtr, void* payload, uint8_t len){
		sub_msg_t* myPayload;
		sizedArray_t* topicSubcribers;
		int err, i; 

		myPayload = (sub_msg_t*)payload;
		// scan the message, and add id of the source mote in the list of subscribed topics
		for(i = 0; i < 3; i++){
			// if the source mote is interested to topic i
			if(myPayload->subscription[i] == 1){
				if((myPayload->qos[i] != 0) && (myPayload->qos[i] != 1)){
					dbg("SUBSCRIBEserver","Subscription rejected: incorrect qos value\n");
					return bufPtr;
				}
				topicSubcribers = getTopicSubscribers(i,myPayload->qos[i]);
				// device is not among the connected ones
				if(!searchID(&connectedDevices,myPayload->ID)){
					dbg("SUBSCRIBEserver","Subscription rejected: unknown device ID\n");
				}
				// add the ID to the subscriber to the topic
				else {
					err = addID(topicSubcribers,myPayload->ID);
					if(err == 0)
						dbg("SUBSCRIBEserver","Subscription rejected: max number of devices exceeded\n");
					else
						dbg("SUBSCRIBEserver","Subscription accepted: mote %hhu subscribed to %hhu, qos:%hhu\n",myPayload->ID,i,myPayload->qos[i]);
				}
			}
		}
		return bufPtr;
	}

	// periodic task, check for published messages to forward
	event void ServerForwardTimer.fired(){
		// using a task here, because this is likely to be 
		// the most expensive operation 
		lockedForwarder = 1;
		// the procedure forwardToSubscribers() takes care of setting lockedForwarder flag back to 0
		// in case there is something to forward
		if(somethingToForward){
			somethingToForward = 0;
			post forwardToSubscribers();
		}
		else{
			lockedForwarder = 0;
		}
	}
	
	// PUBLISHreceiver (AMreceive) interface
	event message_t* PUBLISHreceiver.receive(message_t* bufPtr, void* payload, uint8_t len){
		pub_msg_t* tmp;

		tmp = (pub_msg_t*)payload;
		// only check if this message is equal to the last one; it happens if the ack was lost
		if(lastPublishIDfromClients[tmp->sourceID] == tmp->msgID){
			dbg("PUBLISHserver","PB:Message received twice, discard id %hhu\n",tmp->msgID);
			return bufPtr;
		}
		// else update id of last received msg
		else
			lastPublishIDfromClients[tmp->sourceID] = tmp->msgID;
		// use this flag to check if another message is being forwarded
		// is this is the case, do not modify toBeForwarded because it's being used by forwardToSubscribers task
		if(!lockedForwarder){
			toBeForwarded = tmp;
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
		// here the code separates in client code and server code
		if (isClient()){
			dbg("boot","MQTTclient on\n");
			post initClientStructures();
			call ClientRoutineTimer.startOneShot(CLIENT_AVG_SENSE_PERIOD);
		}
		else{ 
			dbg("boot","MQTTserver on\n");
			post initServerStructures();
			call ServerForwardTimer.startPeriodic(CHECK_FORWARD_PERIODICITY);
		}
	}

}