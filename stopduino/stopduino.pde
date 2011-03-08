
/*
 * Listen for commands to trip relays for a enternet shield equiped arduino
 * 
 * Some code is from Bill Greiman's SdFatLib examples, some is from the Arduino Ethernet
 * WebServer example and some from Limor Fried (Adafruit) so its probably under GPL
 *
 * Tutorial is at http://www.ladyada.net/learn/arduino/ethfiles.html
 * Pull requests for original code should go to http://github.com/adafruit/SDWebBrowse
 */

#include <SdFat.h>
#include <SdFatUtil.h>
#include <Ethernet.h>
#include <SPI.h>

/************ ETHERNET STUFF ************/
byte mac[] = { 0x90, 0xA2, 0xDA, 0x00, 0x38, 0xD2 };
//byte ip[] = { 192, 168, 119, 177 };
byte ip[] = { 172, 18, 4, 196 };
Server server(1984);

/************ light stuff **************/
boolean auth= false;
int numlights=4; // number of elements of the arrays below
boolean states[]={1,1,1,1}; // list of the light/relay states
int pins[]={14,15,16,17}; // list of the light/relay pins
char* lights[]={"red","yellow","green","beacon"}; // list of the "light" lables
char secret[] = "secret";
int blinkc=1;
int blinkmax=20000;

/************ SDCARD STUFF ************/
Sd2Card card;
SdVolume volume;
SdFile root;
SdFile file;

// store error strings in flash to save RAM
#define error(s) error_P(PSTR(s))

void error_P(const char* str) {
  PgmPrint("error: ");
  SerialPrintln_P(str);
  if (card.errorCode()) {
    PgmPrint("SD error: ");
    Serial.print(card.errorCode(), HEX);
    Serial.print(',');
    Serial.println(card.errorData(), HEX);
  }
  while(1);
}

/*********** light/relay routines ****************/

void setlights() { // turn the lights on or off
  for (int i = 0; i < numlights; i++) { // loop through all the lights
    setone(states[i],pins[i]);
  }
}

void getlights() { // turn the lights on or off
  for (int i = 0; i < numlights; i++) { // loop through all the lights
    states[i]=digitalRead(pins[i]);
  }
}

void setone(boolean light, int pin) { //turn on one light
  if (light) {
    digitalWrite(pin,HIGH);
    Serial.print("turning on ");
    Serial.println(pin,DEC);
  } else {
    digitalWrite(pin,LOW);
  }
}

void setstates(boolean newstate) { // set all the states to be on or off
  for (int i = 0; i < numlights; i++) { // loop through all the lights...
    states[i]=newstate;
  }
}

void ListFiles(Client client, uint8_t flags) {
  // This code is just copied from SdFile.cpp in the SDFat library
  // and tweaked to print to the client output in html!
  dir_t p;
  
  root.rewind();
  client.println("<ul>");
  while (root.readDir(p) > 0) {
    // done if past last used entry
    if (p.name[0] == DIR_NAME_FREE) break;

    // skip deleted entry and entries for . and  ..
    if (p.name[0] == DIR_NAME_DELETED || p.name[0] == '.') continue;

    // only list subdirectories and files
    if (!DIR_IS_FILE_OR_SUBDIR(&p)) continue;

    // print any indent spaces
    client.print("<li><a href=\"");
    for (uint8_t i = 0; i < 11; i++) {
      if (p.name[i] == ' ') continue;
      if (i == 8) {
        client.print('.');
      }
      client.print(p.name[i]);
    }
    client.print("\">");
    
    // print file name with possible blank fill
    for (uint8_t i = 0; i < 11; i++) {
      if (p.name[i] == ' ') continue;
      if (i == 8) {
        client.print('.');
      }
      client.print(p.name[i]);
    }
    
    client.print("</a>");
    
    if (DIR_IS_SUBDIR(&p)) {
      client.print('/');
    }

    // print modify date/time if requested
    if (flags & LS_DATE) {
       root.printFatDate(p.lastWriteDate);
       client.print(' ');
       root.printFatTime(p.lastWriteTime);
    }
    // print size if requested
    if (!DIR_IS_SUBDIR(&p) && (flags & LS_SIZE)) {
      client.print(' ');
      client.print(p.fileSize);
    }
    client.println("</li>");
  }
  client.println("</ul>");
}

void doform(Client client) {  // draw the form
  client.println("<form action='b' action='get'>");
  for (int i = 0; i < numlights; i++) { // loop through all the lights
    dobox(client,lights[i],states[i]);
  }
  client.println("<input type='password' name='a'><br>");
  client.println("</form>");
}

void dobox(Client client,char item[], boolean checked) {  // draw a single checkbox
  client.print("<input type='checkbox' name='c' value='");
  client.print(item);
  client.print("'");
  if (checked) {
    client.print(" checked");
  }
  client.print(">");
  client.print(item);
  client.println("<br>");
}

// How big our line buffer should be. 100 is plenty!
#define BUFSIZ 100

void setup() {
  Serial.begin(9600);
 
  PgmPrint("Free RAM: ");
  Serial.println(FreeRam());  
  
  // set pins as output and turn on all the lights to show that we don't have access yet.
  for (int i = 0; i < numlights; i++) { // loop through all the lights
    pinMode(pins[i], OUTPUT);
  }
  setlights();
  
  pinMode(10, OUTPUT);                       // set the SS pin as an output (necessary!)
  digitalWrite(10, HIGH);                    // but turn off the W5100 chip!
/*
  if (!card.init(SPI_HALF_SPEED, 4)) error("card.init failed!");
  
  // initialize a FAT volume
  if (!volume.init(&card)) error("vol.init failed!");

  PgmPrint("Volume is FAT");
  Serial.println(volume.fatType(),DEC);
  Serial.println();
  
  if (!root.openRoot(&volume)) error("openRoot failed");

  // list file in root with date and size
  PgmPrintln("Files found in root:");
  root.ls(LS_DATE | LS_SIZE);
  Serial.println();
  
  // Recursive list of all directories
  PgmPrintln("Files found in all dirs:");
  root.ls(LS_R);
  
  Serial.println();
  PgmPrintln("Done");
*/  
  // Debugging complete, we start the server!
  Ethernet.begin(mac, ip);
  server.begin();
}


void loop()
{
  char clientline[BUFSIZ];
  int index = 0;
  
  Client client = server.available();
  if (client) {
    // an http request ends with a blank line
    boolean current_line_is_blank = true;
    
    // reset the input buffer
    index = 0;
    
    while (client.connected()) {
      if (client.available()) {
        char c = client.read();
        
        // If it isn't a new line, add the character to the buffer
        if (c != '\n' && c != '\r') {
          clientline[index] = c;
          index++;
          // are we too big for the buffer? start tossing out data
          if (index >= BUFSIZ) 
            index = BUFSIZ -1;
          
          // continue to read more data!
          continue;
        }
        
        // got a \n or \r new line, which means the string is done
        clientline[index] = 0;
        
        // Print it out for debugging
        Serial.println(clientline);
        
        // Look for substring such as a request to get the root file
        if (strstr(clientline, "GET / ") != 0) {
          // send a standard http response header
          client.println("HTTP/1.1 200 OK");
          client.println("Content-Type: text/html");
          client.println();
          doform(client);
          client.print("Free Ram: ");
          client.println(FreeRam());        
        } else if (strstr(clientline, "GET /") != 0) {
          // this time no space after the /, so a request!
          char *request;
          request = clientline + 5; // look after the "GET /" (5 chars)
          // a little trick, look for the " HTTP/1.1" string and 
          // turn the first character of the substring into a 0 to clear it out.
          (strstr(clientline, " HTTP"))[0] = 0;
          // print the requested string
          Serial.println(request);
/*
          if (! file.open(&root, filename, O_READ)) {
            client.println("HTTP/1.1 404 Not Found");
            client.println("Content-Type: text/html");
            client.println();
            client.println("<h2>File Not Found!</h2>");
            break;
          }
          Serial.println("Opened!");
*/          
          client.println("HTTP/1.1 200 OK");
          client.println("Content-Type: text/html");
          client.println();
          auth= false;  // assume, until proven different, that the request is not authenticated
          for (int i = 0; i < numlights; i++) { // loop through all the lights...
            states[i]=false;  // ...and assume they are off
          }
          if (strstr(request, (const char *)secret) !=0) {
            client.println("<h2>Authenticated</h2>");
            auth= true;
          } else{
            client.println("<h2>Not Authenticated, so NOT...</h2>");
          }
          for (int i = 0; i < numlights; i++) { // loop through all the lights...
            states[i]=false;  // ...and assume they are off
            if (strstr(request, lights[i]) != 0){ // if they asked for this light
              client.print("Turning ");
              client.print(lights[i]);
              client.println(" on<br>");
              if (auth){ //actually do it
                states[i]=true;
              } // end of "auth" 
            }  // end of "asked for this light"     
          }   // end of light loop

          if (auth) { // now that all the colors are set, change the lights
            setlights();
            blinkc=0; // stop blinking
          }
          getlights(); // get the current settings before...
          doform(client); // ... drawing the form

/*
          int16_t c;
          while ((c = file.read()) > 0) {
              // uncomment the serial to debug (slow!)
              //Serial.print((char)c);
              client.print((char)c);
          }
          file.close();
*/
        } else {
          // everything else is a 404
          client.println("HTTP/1.1 404 Not Found");
          client.println("Content-Type: text/html");
          client.println();
          client.println("<h2>HUH?</h2>");
        }
        break;
      }
    }
    // give the web browser time to receive the data
    delay(1);
    client.stop();
  }
/*******************************************
 *  when first turned on, blink the lights
 *    once blinkc is set to 0, it won't blink any more.
 ******************************************/
  if (blinkc == 1 ) { // turn on
    Serial.println("On");
    setstates(true);
    setlights();
    blinkc++;
  } else if (blinkc == (blinkmax/2)) { // half way through, turn off
    Serial.println("Off");
    setstates(false);
    setlights();
  } else if (blinkc > blinkmax) { // reset loop
    blinkc=1;
  }
  if (blinkc >1 ) { // increment loop if counter is set
    blinkc++;
  }
}

