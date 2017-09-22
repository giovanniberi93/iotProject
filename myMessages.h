#ifndef MY_MSGS_MQTT_H
#define MY_MSGS_MQTT_H

// max amount of devices connected
#define MAX_CONNECTED 16

// max amount of time between an event and the following one
// in the client
// expressed in milliseconds
#define MAX_INTERVAL_CLIENT 1500

#define TEMPERATURE 0
#define HUMIDITY 1
#define LUMINOSITY 2
#define NO_SUBS 3

// definition of the message structure
typedef nx_struct connect_msg{
	nx_int16_t ID;
} connect_msg_t;

typedef nx_struct sub_msg{
	nx_int16_t ID;
	nx_int16_t subscription;
	nx_int16_t qos;
} sub_msg_t;

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