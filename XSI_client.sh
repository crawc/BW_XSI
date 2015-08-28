#!/bin/bash

#CONFIG
. config;

#Basic auth
CRED64=$(echo -n "${USER}:${PASS}" | base64);

#Default headers
AUTHORIZATION='Authorization: Basic '"$CRED64";
HOSTH='Host: '"$HTTPHOST";
CTYPE='Content-Type: application/x-www-form-urlencoded';


subscribe ()
{
    #create channel set
    CPOST='POST /com.broadsoft.async/com.broadsoft.xsi-events/v2.0/channel HTTP/1.1';
    CSET='<?xml version="1.0" encoding="UTF-8"?><Channel xmlns="http://schema.broadsoft.com/xsi"><channelSetId>ChannelSetIdOne</channelSetId><priority>1</priority><weight>100</weight><expires>'"$EXPIRES"'</expires></Channel>';
    clen=$(echo -n "$CSET" | wc -c);
    CLEN='Content-Length: '"$clen";
    exec 3<>/dev/tcp/"$HOST"/"$PORT";
    echo -e "${CPOST}\n${AUTHORIZATION}\n${HOSTH}\n${CLEN}\n${CTYPE}\n\n${CSET}\n" >&3;
    RESP=$(head -n1 <&3);

    #subscribe channel
    CHANPOST='POST /com.broadsoft.xsi-events/v2.0/User/'"${USER}"'/subscription'' HTTP/1.1';
    CHANSET='<?xml version="1.0" encoding="UTF-8"?><Subscription xmlns="http://schema.broadsoft.com/xsi"><targetIdType>User</targetIdType><event>Basic Call</event><expires>'"$EXPIRES"'</expires><channelSetId>ChannelSetIdOne</channelSetId><applicationId>CommPilotApplication</applicationId></Subscription>';
    chanlen=$(echo -n "$CHANSET" | wc -c);
    CHANLEN='Content-Length: '"$chanlen";
    exec 4<>/dev/tcp/"$HOST"/"$PORT";
    echo -e "${CHANPOST}\n${AUTHORIZATION}\n${HOSTH}\n${CHANLEN}\n${CTYPE}\n\n${CHANSET}\n" >&4;
    RESP=$(head -n1 <&4);
    exec 4>&-;
}


subsDATE=$(date +%s);
subscribe;
gcID="";
sDATE=$(date +%s);

#read from channel set
while true; do
    RESP="";
    cBUFF=0;
    cBUFF=$(ss -natp 2>/dev/null | awk -v pid=$$ '{ if ($0~pid) print $2}');
#'''
    if [ "$cBUFF" != "" ]; then
        if [ $cBUFF -gt 0 ]; then
            RESP=$(head -c $cBUFF <&3);
        fi;
    fi;

    if [ "$RESP" != "" ]; then
        date;
        echo "$RESP";
        eID=$(echo "$RESP" | awk 'BEGIN {RS="><";} { if ($0~"eventID") {gsub (">|<",";");split($0,a,";");print a[2]} }');
        cID=$(echo "$RESP" | awk 'BEGIN {RS="><";} { if ($0~"channelId") {gsub (">|<",";");split($0,a,";");print a[2]}}');
#'''
        if [ "$gcID" == "" ]; then
            if [ "$cID" != "" ]; then
                gcID="$cID";
            fi;
        fi;

        if [ "$eID" != "" ]; then
            echo "$eID" | while read eIDs; do
                exec 4<>/dev/tcp/"$HOST"/"$PORT";
                CONFPOST='POST /com.broadsoft.xsi-events/v2.0/channel/eventresponse HTTP/1.1';
                CONFSET='<?xml version="1.0" encoding="UTF-8"?><EventResponse xmlns="http://schema.broadsoft.com/xsi"><eventID>'"$eIDs"'</eventID><statusCode>200</statusCode><reason>OK</reason></EventResponse>';
                conflen=$(echo -n "$CONFSET" | wc -c);
                CONFLEN='Content-Length: '"$conflen";
                echo -e "${CONFPOST}\n${AUTHORIZATION}\n${HOSTH}\n${CONFLEN}\n${CTYPE}\n\n${CONFSET}\n" >&4;
                RESP=$(head -n1 <&4);
                exec 4>&-;
                sleep 1;
            done;
        fi;
    fi;

    nDATE=$(date +%s);
    let delta=$nDATE-$sDATE;

    if [ $delta -ge 5 ]; then
        if [ "$gcID" != "" ]; then
            exec 4<>/dev/tcp/"$HOST"/"$PORT";
            PUTHEARTBEAT='PUT /com.broadsoft.xsi-events/v2.0/channel/'"$gcID"'/heartbeat HTTP/1.1';
            echo -e "${PUTHEARTBEAT}\n${AUTHORIZATION}\n${HOSTH}\n" >&4;
            exec 4>&-;
        fi;
        sDATE="$nDATE";
    fi;

    let subsdelta=$nDATE-$subsDATE;
    let subsdelta=$subsdelta*2;

    if [ $subsdelta -gt $EXPIRES ]; then
        exec 3>&-;
        subsDATE=$(date +%s);
        subscribe;
        gcID="";
        sDATE=$(date +%s);
    fi;

done;
exec 3>&-;
