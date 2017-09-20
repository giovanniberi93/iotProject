#ifndef MY_MSGS_MQTT_H
#define MY_MSGS_MQTT_H

// max amount of devices connected
#define MAX_CONNECTED 16

// definition of the message structure
typedef nx_struct connect_msg{
	nx_int16_t ID;
} connect_msg_t;

// data structure built to store subscriptions
typedef nx_struct arr{
	nx_int16_t counter;
	nx_int16_t IDs[MAX_CONNECTED];
} sizedArray_t;

// Active messages definition
enum{
	CONNECT = 6,
	PUBLISH = 7,
	SUBSCRIBE = 8,
};

#endif