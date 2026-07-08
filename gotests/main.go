package main

import (
	"fmt"
	"io"
	"log"
	"net"

	"github.com/knusbaum/go9p/client"
	"github.com/knusbaum/go9p/proto"
)

func main() {
	s, err := net.Dial("tcp", "localhost:4000")
	if err != nil {
		log.Fatal(err)
	}
	c, err := client.NewClient(s, "test", "")
	if err != nil {
		log.Fatal(err)
	}
	f, err := c.Open("/file1.txt", proto.Oread)
	if err != nil {
		log.Fatal(err)
	}
	defer f.Close()
	bs, err := io.ReadAll(f)
	log.Printf("RECEIVED: [%s]\n", string(bs))

	new_file_path := "/new_file.txt"
	f2, err := c.Create(new_file_path, 0666)
	if err != nil {
		f2, err = c.Open(new_file_path, proto.Ordwr)

		if err != nil {
			log.Fatal(err)
		}
	}

	fmt.Println("Writing to new file")
	second_file_text := "This is a new file"
	if _, err := f2.Write([]byte(second_file_text)); err != nil {
		log.Fatal(err)
	}
	buf := make([]byte, 100)
	n, err := f2.ReadAt(buf, 0)

	if err != nil && err.Error() != "EOF" {
		log.Fatalf("ReadAt failed: %v", err)
	}
	fmt.Printf("Successfully read %d bytes: %s\n", n, string(buf[:n]))

	stat, err := c.Stat(new_file_path)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Got stat %s", stat.String())

	log.Printf("Reading directory /\n")

	dir, err := c.Readdir("/")

	if err != nil {
		log.Fatal(err)
	}

	for _, st := range dir {
		fmt.Println(st.Name)

	}

}
