
import processing.video.*;

import oscP5.*;
import netP5.*;

Capture cam;

PImage lastCam;

OscP5 oscP5;
NetAddress myRemoteLocation;

ArrayList<Integer>   idValues = new ArrayList<Integer>();
ArrayList<Float>    durValues = new ArrayList<Float>();
ArrayList<Float>   gainValues = new ArrayList<Float>();
ArrayList<Float>  pitchValues = new ArrayList<Float>();
ArrayList<Integer> beatValues = new ArrayList<Integer>();

int cameraIndex=0;

PImage background;
int nbTypes = 3;
int nbFinalTypes = 3;
float[] typeColors = new float[nbTypes];
int nbBeats = 16;
float maxPitch = 24;// number of semitones

int currentBeat=0;
int showLabel = 0;

Token[] tokens;

int[][] tokensIds;// only for debug

// detection parameters
float backgroundThreshold = 0x15;
float saturationThreshold = 0x50;
int maxTokens = 32;
int sizeThreshold = 10;
int closenessLimit = 0x05;// remove one color if too similar to another
int detectionW = 160;
int detectionH = 120;

boolean realTimeDetection = true;

void setup() {

  size(800, 600);

  colorMode(HSB);

  String[] camList = Capture.list(); 
  for (int i=0; i<camList.length; i++) println(i+" "+camList[i]);
  cam = new Capture(this, camList[cameraIndex]);
  cam.start();

  oscP5 = new OscP5(this, 12000);
  myRemoteLocation = new NetAddress("127.0.0.1", 12001);

  // from pure data
  oscP5.plug(this, "handshake", "/handshake");
  oscP5.plug(this, "currentBeat", "/currentBeat");
  oscP5.plug(this, "requestNbBeats", "/requestNbBeats");
  oscP5.plug(this, "requestMaxPitch", "/requestMaxPitch");
  oscP5.plug(this, "requestScaleDivision", "/requestScaleDivision");
  oscP5.plug(this, "requestBackgroundThreshold", "/requestBackgroundThreshold");
  oscP5.plug(this, "requestSaturationThreshold", "/requestSaturationThreshold");
  oscP5.plug(this, "requestMaxTokens", "/requestMaxTokens");
  oscP5.plug(this, "requestSizeThreshold", "/requestSizeThreshold");
  oscP5.plug(this, "requestClosenessLimit", "/requestClosenessLimit");
  oscP5.plug(this, "requestDetectionW", "/requestDetectionW");
  oscP5.plug(this, "requestDetectionH", "/requestDetectionH");
  oscP5.plug(this, "requestCaptureProcessing", "/requestCaptureProcessing");
  oscP5.plug(this, "requestBackgroundCapture", "/requestBackgroundCapture");

  background = loadImage(dataPath("defaultBackground.png"));
}

void draw() {
  if (cam.available()) {
    cam.read();
    lastCam = cam.get();
    if (realTimeDetection) {
      processPicture();
      fillTables();
      sendTables();
    }
  }
  if (lastCam!=null) {
    image(lastCam, 0, 0, width, height);
  } else {
    background(0);
  }
  if (tokensIds!=null) {
    for (int x=0; x<tokensIds.length; x++) {
      for (int y=0; y<tokensIds[x].length; y++) {
        if (tokensIds[x][y]!=-1) {
          noStroke();
          fill(typeColors[tokensIds[x][y]], 0x80, 0x80);
          rect((float)(x)*width/tokensIds.length, (float)(y)*height/tokensIds[x].length, (float)width/tokensIds.length, (float)height/tokensIds[x].length);
        }
      }
    }
  }
  if (tokens!=null) {
    for (Token token : tokens) {
      noFill();
      stroke(typeColors[token.id], 0xFF, 0xFF);
      line(token.avgX*(float)width/token.w, token.minY*(float)height/token.h, token.avgX*(float)width/token.w, (token.maxY+1)*(float)height/token.h);
      line(token.minX*(float)width/token.w, token.avgY*(float)height/token.h, (token.maxX+1)*(float)width/token.w, token.avgY*(float)height/token.h);
      ellipse(floor(token.minX*nbBeats/token.w)*(float)width/nbBeats+(0.5f)*(float)width/nbBeats, token.avgY*(float)height/token.h, 5, 5);
      line(token.minX*(float)width/token.w, token.avgY*(float)height/token.h-2, token.minX*(float)width/token.w, token.avgY*(float)height/token.h+2);
    }
  }
  stroke(0xFF, 0x80);
  for (int i=0; i< (maxPitch); i++) {
    line(0, (float)i*height/(maxPitch), width, (float)i*height/(maxPitch));
  }
  for (int i=0; i<nbBeats; i++) {
    line((float)i*width/nbBeats, 0, (float)i*width/nbBeats, height);
  }
  noStroke();
  fill(0xFF, 0x80);
  rect((float)currentBeat*width/nbBeats, 0, (float)width/nbBeats, height);
  fill(0xFF);
  ArrayList toShow = null;
  if (showLabel==1) toShow=idValues;
  if (showLabel==2) toShow=durValues;
  if (showLabel==3) toShow=gainValues;
  if (showLabel==4) toShow=pitchValues;
  if (showLabel==5) toShow=beatValues;
  if (showLabel==1) text("id", 20, 20);
  if (showLabel==2) text("duration", 20, 20);
  if (showLabel==3) text("gain", 20, 20);
  if (showLabel==4) text("pitch", 20, 20);
  if (showLabel==5) text("beat", 20, 20);
  if (toShow!=null) for (int i=0; i<tokens.length; i++) text(toShow.get(i).toString(), tokens[i].avgX*width/tokens[i].w, tokens[i].avgY*height/tokens[i].h);
}

void keyPressed() {
  if (keyCode==LEFT) {
    realTimeDetection = !realTimeDetection;
  }
  if (keyCode==UP) {
    requestBackgroundCapture();
  } 
  if (keyCode==ENTER) {
    processPicture();
    fillTables();
    sendTables();
  }
  if (keyCode==TAB) showLabel = (showLabel+1)%6;
}

void fillTables() {
  IntList foundTypes = new IntList();
  for (Token token : tokens) if (!foundTypes.hasValue(token.id)) foundTypes.append(token.id);
  nbFinalTypes = foundTypes.size();
  float maxGain=1;
  for (int i=0; i<tokens.length; i++) {
    maxGain=max(maxGain, tokens[i].maxY-tokens[i].minY);
  }
  idValues.clear();
  durValues.clear();
  gainValues.clear();
  pitchValues.clear();
  beatValues.clear();
  for (int i=0; i<tokens.length; i++) {
    idValues.add(tokens[i].id);
    durValues.add(((float)tokens[i].maxX-tokens[i].minX)/tokens[i].w*nbBeats);
    gainValues.add((tokens[i].maxY-tokens[i].minY)/maxGain);
    pitchValues.add(maxPitch-(tokens[i].avgY/tokens[i].h*maxPitch));
    beatValues.add(floor(tokens[i].minX/tokens[i].w*nbBeats));
  }
}

void currentBeat(int b) {
  currentBeat=b;
}

void requestNbBeats(int b) {
  nbBeats=b;
}

void requestMaxPitch(int m) {
  maxPitch=m;
}

void requestBackgroundThreshold(int b) {
  backgroundThreshold=b;
}

void requestSaturationThreshold(int s) {
  saturationThreshold=s;
}

void requestMaxTokens(int m) {
  maxTokens=m;
}

void requestSizeThreshold(int s) {
  sizeThreshold=s;
}

void requestClosenessLimit(int c) {
  closenessLimit = c;
}

void requestDetectionW(int l) {
  detectionW = max(l, 1);
}

void requestDetectionH(int l) {
  detectionH = max(l, 1);
}

void processPicture() {
  tokens = defineTokenIds(lastCam.get(), background);
}

void requestCaptureProcessing(int o) {
  realTimeDetection = (o==1);
}

void requestBackgroundCapture() {
  background=lastCam.get();
  background.save(dataPath("defaultBackground.png"));
}

void sendTables() {
  try {
    OscMessage myOscMessage;
    myOscMessage = new OscMessage("/nbFinalTypes");
    myOscMessage.add(nbFinalTypes);
    oscP5.send(myOscMessage, myRemoteLocation);
    myOscMessage = new OscMessage("/maxPitch");
    myOscMessage.add(maxPitch);
    oscP5.send(myOscMessage, myRemoteLocation);
    myOscMessage = new OscMessage("/nbNotes");
    myOscMessage.add(tokens.length);
    oscP5.send(myOscMessage, myRemoteLocation);
    myOscMessage = new OscMessage("/nbBeats");
    myOscMessage.add(nbBeats);
    oscP5.send(myOscMessage, myRemoteLocation);
    myOscMessage = new OscMessage("/tId");
    myOscMessage.add(idValues.toArray());
    oscP5.send(myOscMessage, myRemoteLocation);
    myOscMessage = new OscMessage("/tDur");
    myOscMessage.add(durValues.toArray());
    oscP5.send(myOscMessage, myRemoteLocation);
    myOscMessage = new OscMessage("/tGain");
    myOscMessage.add(gainValues.toArray());
    oscP5.send(myOscMessage, myRemoteLocation);
    myOscMessage = new OscMessage("/tPitch");
    myOscMessage.add(pitchValues.toArray());
    oscP5.send(myOscMessage, myRemoteLocation);
    myOscMessage = new OscMessage("/tBeat");
    myOscMessage.add(beatValues.toArray());
    oscP5.send(myOscMessage, myRemoteLocation);
  }
  catch (Exception e) {
    println("recOn : "+e);
  }
}

void handshake() {
}

Token[] defineTokenIds(PImage im, PImage bg) {
  PImage im2 = im.get();
  im2.resize(detectionW, detectionH);
  im2.filter(BLUR, 1);
  PImage bg2 = bg.get();
  bg2.resize(detectionW, detectionH);
  bg2.filter(BLUR, 1);
  int[][] ids = new int[im2.width][im2.height];
  for (int x=0; x<im2.width; x++) {
    for (int y=0; y<im2.height; y++) {
      ids[x][y]=-1;
    }
  }
  // set non background colors id to 0


  for (int x=0; x<im2.width; x++) {
    for (int y=0; y<im2.height; y++) {
      if (colorDiff(im2.get(x, y), bg2.get(x, y))>backgroundThreshold) {
        ids[x][y]=0;
      }
    }
  }
  // disable id if not saturated
  for (int x=0; x<im2.width; x++) {
    for (int y=0; y<im2.height; y++) {
      if (saturation(im2.get(x, y))<saturationThreshold) {
        ids[x][y]=-1;
      }
    }
  }
  // set an array of non null color hues
  FloatList presentHues = new FloatList();
  for (int x=0; x<im2.width; x++) {
    for (int y=0; y<im2.height; y++) {
      if (ids[x][y]!=-1) {
        presentHues.append(hue(im2.get(x, y)));
      }
    }
  }
  // define three average colors using findGroups() put them in typeColors
  typeColors = findGroups(presentHues.array(), 3, 0x100);
  // set each id to the closest color model
  for (int x=0; x<im2.width; x++) {
    for (int y=0; y<im2.height; y++) {
      if (ids[x][y]!=-1) {
        float bestProximity=-1;
        for (int i=0; i<nbTypes; i++) {
          float thisProximity = abs(vrMax(hue(im2.get(x, y)), typeColors[i], 0x100));
          if (bestProximity==-1||thisProximity<=bestProximity) {
            bestProximity=thisProximity;
            ids[x][y]=i;
          }
        }
      }
    }
  }
  // define token ids for each group of adjacent points and keep track of the target id
  ArrayList<Token> tokens = new ArrayList<Token>();
  Token[][] tokenRefs = new Token[im2.width][im2.height]; 
  for (int x=0; x<im2.width; x++) {
    for (int y=0; y<im2.height; y++) {
      if (ids[x][y]==-1) {
        // empty id
      } else {
        if (y>0) {
          if (ids[x][y-1]==ids[x][y]) {
            tokenRefs[x][y]=tokenRefs[x][y-1];
            tokenRefs[x][y].addPixel(x+y*im2.width);
          }
        }
        if (x>0) {
          if (ids[x-1][y]==ids[x][y]) {
            if (tokenRefs[x][y]!=null) {
              if (tokenRefs[x-1][y]!=tokenRefs[x][y]) {
                tokenRefs[x][y].mergeToThis(tokenRefs, tokenRefs[x-1][y]);
              }
            } else {
              tokenRefs[x][y]=tokenRefs[x-1][y];
              tokenRefs[x][y].addPixel(x+y*im2.width);
            }
          }
        }
        if (tokenRefs[x][y]==null) {
          // new token
          tokenRefs[x][y] = new Token(ids[x][y], im2.width, im2.height);
          tokenRefs[x][y].addPixel(x+y*im2.width);
          tokens.add(tokenRefs[x][y]);
        }
      }
    }
  }
  // remove unused Tokens
  ArrayList<Token> tokensToRemove = new ArrayList<Token>();
  for (Token token : tokens) {
    boolean found=false;
    for (int x=0; x<im2.width && !found; x++) {
      for (int y=0; y<im2.height && !found; y++) {
        if (tokenRefs[x][y]==token) found=true;
      }
    }
    if (!found) tokensToRemove.add(token);
  }
  // remove small groups
  for (Token token : tokens) if (token.pixelIds.size()<sizeThreshold) tokensToRemove.add(token);
  for (Token token : tokensToRemove) if (tokens.contains(token)) tokens.remove(token);
  // limit number of tokens
  while (tokens.size ()>maxTokens && maxTokens>0) {
    Token smallestToken = tokens.get(0);
    for (Token token : tokens) {
      if (token.pixelIds.size()<smallestToken.pixelIds.size()) {
        smallestToken=token;
      }
    }
    tokens.remove(smallestToken);
  }
  // commit tokens
  for (Token token : tokens) token.commit();
  tokensIds=ids;
  // println("tokens size : "+tokens.size());
  return tokens.toArray(new Token[0]);
}

class Token {
  // defined during analysis
  IntList pixelIds = new IntList();
  int id;
  int w, h;

  // defined after commit
  float avgX, avgY;
  float minX, maxX, minY, maxY;

  Token(int id, int w, int h) {
    this.id=id;
    this.w=w;
    this.h=h;
  }

  void addPixel(int p) {
    pixelIds.append(p);
  }

  void mergeToThis(Token[][] tokenRefs, Token oldToken) {
    for (int x=0; x<tokenRefs.length; x++) {
      for (int y=0; y<tokenRefs[x].length; y++) {
        if (tokenRefs[x][y]==oldToken) {
          addPixel(x+y*tokenRefs.length);
          tokenRefs[x][y]=this;
        }
      }
    }
  }

  void commit() {
    avgX=avgY=0;
    minX=w;
    maxX=0;
    minY=h;
    maxY=0;
    for (int tId : pixelIds) {
      int thisX = tId%w;
      int thisY = floor((float)tId/w);
      avgX += thisX;
      avgY += thisY;
      minX = min(minX, thisX);
      maxX = max(maxX, thisX);
      minY = min(minY, thisY);
      maxY = max(maxY, thisY);
    }
    avgX /= pixelIds.size();
    avgY /= pixelIds.size();
  }
}

float colorDiff(color a, color b) {
  return abs(red(a)-red(b))+abs(green(a)-green(b))+abs(blue(a)-blue(b));
}

public float vrMax(float a, float b, float m) {
  float d1=b-a;
  if (d1>m/2)  d1=d1-m;
  if (d1<-m/2) d1=d1+m;
  return d1;
}

float[] findGroups(float[] numbers, int nbGroups, int max) {
  float[] groupValues = new float[nbGroups];
  if (numbers.length>0) {
    for (int i=0; i<nbGroups; i++) {
      if (i==0) {
        groupValues[i]=numbers[0];
      } else {
        int bestJ=0;
        for (int j=0; j<numbers.length; j++) {
          for (int k=0; k<i; k++) {
            if (abs(vrMax(numbers[j], groupValues[k], max))>abs(vrMax(numbers[bestJ], groupValues[k], max))) {
              bestJ=j;
            }
          }
        }
        groupValues[i] = numbers[bestJ];
      }
    }
    float biggestChange=-1;
    int nbIter=0;
    while (biggestChange==-1||biggestChange>1||nbIter>100) {
      float[] groupDiffs = new float[nbGroups];
      for (int i=0; i<nbGroups; i++) {
        groupDiffs[i]=0;
        int nbNumbersInThisGroup=0;
        for (int j=0; j<numbers.length; j++) {
          int belongsToGroup=0;
          float bestDiff=vrMax(groupValues[belongsToGroup], numbers[j], max);
          for (int k=1; k<nbGroups; k++) {
            float thisDiff = vrMax(groupValues[k], numbers[j], max);
            if (abs(thisDiff)<abs(bestDiff)) {
              bestDiff=thisDiff;
              belongsToGroup=k;
            }
          }
          // belongs[j]=belongsToGroup;
          if (belongsToGroup==i) {
            groupDiffs[i]+=bestDiff;
            nbNumbersInThisGroup++;
          }
        }
        groupDiffs[i]/=max(nbNumbersInThisGroup, 1);
      }
      biggestChange=-1;
      for (int i=0; i<nbGroups; i++) {
        if (biggestChange==-1||biggestChange<abs(groupDiffs[i])) biggestChange=abs(groupDiffs[i]);
      }
      for (int i=0; i<nbGroups; i++) {
        groupValues[i]=(groupValues[i]+groupDiffs[i]);
        while (groupValues[i]<0||groupValues[i]>=max) groupValues[i]=(groupValues[i]+max)%max;
      }
      nbIter++;
    }
  }
  for (int i=0; i<nbGroups; i++) {
    for (int j=0; j<nbGroups; j++) {
      if (i!=j) {
        if (abs(vrMax(groupValues[i], groupValues[j], 0x100))<closenessLimit) {
          groupValues[i]=groupValues[j];
        }
      }
    }
  }
  return groupValues;
}
