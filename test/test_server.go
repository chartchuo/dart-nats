package main

import (
	nats "github.com/nats-io/nats.go"
	"log"
	"time"
)

func main() {
	nc, err := nats.Connect("localhost")
	if err != nil {
		log.Fatal(err)
	}
	defer nc.Close()

	// Create a unique subject name for replies.
	uniqueReplyTo := nats.NewInbox()

	// Listen for a single response
	sub, err := nc.SubscribeSync(uniqueReplyTo)
	if err != nil {
		log.Fatal(err)
	}
	// Send the request.
	// If processing is synchronous, use Request() which returns the response message.
	if err := nc.PublishRequest("time", uniqueReplyTo, nil); err != nil {
		log.Fatal(err)
	}
	// Read the reply
	msg, err := sub.NextMsg(time.Second)
	if err != nil {
		log.Fatal(err)
	}
	// Use the response
	log.Printf("Reply: %s", msg.Data)

}
