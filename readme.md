Implementation of a lightweight publish-subscribe application protocol for TinyOS

// cose da dire
	- stesso firmware per client server, si separano nella fase di boot
	- messaggi diversi si basano su AM id diversi
	- setting non casuale, ma che copre un po' di casi
	- id del msg per rimuovere duplicati:
		- in connect non fa niente
		- in subscribe non fa niente
		- in publish va fatto
		- in forward va fatto
	- si incasina se 2 dati arrivano "assieme", risolvibile con un buffer che è un bordello
	- tecnica di forwarding basata sul senddone
	- id per rimozione duplicati, uno per ogni client per publish, 1 solo per forward
	- pacchetto scarta quelli che vengono da lui stesso
