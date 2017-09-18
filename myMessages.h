#ifndef MY_MSGS_MQTT_H
#define MY_MSGS_MQTT_H

typedef nx_struct send_value_msg{
	nx_int16_t msg_value;
} send_value_msg_t;

enum{
	SEND_VALUE_MSG = 6,
};

#endif