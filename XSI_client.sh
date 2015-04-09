#!/bin/bash

#CONFIG
. config;

#Basic auth
CRED64=$(echo -n "${USER}:${PASS}" | base64);

#Default headers
PUTHEARTBEAT='PUT /com.broadsoft.xsi-events/v2.0/channel/ChangeID/heartbeat HTTP/1.1';
AUTHORIZATION="Authorization: Basic $CRED64";
HOSTH="Host: $HOST";
CTYPE='Content-Type: application/x-www-form-urlencoded';

CPOST='POST /com.broadsoft.async/com.broadsoft.xsi-events/v2.0/channel HTTP/1.1';
CSET='<Channel xmlns="http://schema.broadsoft.com/xsi"><channelSetId>ChannelSetIdOne</channelSetId><priority>1</priority><weight>100</weight><expires>3600</expires></Channel>';
clen=$(echo -n "$CSET" | wc -c);
CLEN="Content-Length: $clen";

CHANPOST="POST /com.broadsoft.xsi-events/v2.0/User/${USER} HTTP/1.1";
CHANSET='<?xml version="1.0" encoding="UTF-8"?><Subscription xmlns="http://schema.broadsoft.com/xsi"><event>Basic Call</event><expires>3600</expires><channelSetId>ChannelSetIdOne</channelSetId><applicationId>CommPilotApplication</applicationId></Subscription>';
chanlen=$(echo -n "$CHANSET" | wc -c);
CHANLEN="Content-Length: $chanlen";

CONFPOST="POST /com.broadsoft.xsi-events/v2.0/channel/eventresponse HTTP/1.1";
CONFLEN='Content-Length: 211';
CONFSET='<?xml version="1.0" encoding="UTF-8"?><EventResponse xmlns="http://schema.broadsoft.com/xsi"><eventID>ChangeID</eventID><statusCode>200</statusCode><reason>OK</reason></EventResponse>';

#create channel set
exec 3<>/dev/tcp/"$HOST"/"$PORT";
echo -e "${CPOST}\n${AUTHORIZATION}\n${HOSTH}\n${CLEN}\n${CTYPE}\n\n${CSET}\n" >&3;
RESP=$(head -n1 <&3);

#subscribe channel
exec 4<>/dev/tcp/"$HOST"/"$PORT";
echo -e "${CHANPOST}\n${AUTHORIZATION}\n${HOSTH}\n${CHANLEN}\n${CTYPE}\n\n${CHANSET}\n" >&4;
RESP=$(head -n1 <&4);
exec 4>&-;

#read from channel set
gcID="";
sDATE=$(date +%s);
while true; do
    RESP="";
    cBUFF=0;
    cBUFF=$(netstat -napt 2>/dev/null | awk -v pid=$$ '{ if ($0~pid) print $2}');
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
        if [ "$gcID" == "" ]; then
            if [ "$cID" != "" ]; then
                gcID="$cID";
            fi;
        fi;

        if [ "$eID" != "" ]; then
            exec 4<>/dev/tcp/"$HOST"/"$PORT";
            echo -e "${CONFPOST}\n${AUTHORIZATION}\n${HOSTH}\n${CONFLEN}\n${CTYPE}\n\n${CONFSET}\n" | sed "s/ChangeID/"$eID"/;" >&4;
            RESP=$(head -n1 <&4);
            exec 4>&-;
        fi;
    fi;

    nDATE=$(date +%s);
    let delta=$nDATE-$sDATE;

    if [ $delta -ge 5 ]; then
        if [ "$gcID" != "" ]; then
            exec 4<>/dev/tcp/"$HOST"/"$PORT";
            echo -e "${PUTHEARTBEAT}\n${AUTHORIZATION}\n${HOSTH}\n" | sed "s/ChangeID/"$gcID"/;" >&4;
            exec 4>&-;
        fi;
        sDATE="$nDATE";
    fi;
done;
exec 3>&-;
