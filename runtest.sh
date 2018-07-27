#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of ompipe-message-lost
#   Description: Simple test of ompipe rsyslog module
#   Author: Radovan Sroka <rsroka@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2018 Red Hat, Inc. All rights reserved.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include rhts environment
. /usr/bin/rhts-environment.sh
. /usr/lib/beakerlib/beakerlib.sh

PACKAGE="rsyslog"
PACKAGE="${COMPONENT:-$PACKAGE}"

rlJournalStart
    rlPhaseStartSetup
        rlRun "rlImport --all" || rlDie 'cannot continue'
        rlRun "rlCheckMakefileRequires" || rlDie 'cannot continue'
        rlFileBackup /etc/rsyslog.conf
        rlFileBackup /etc/systemd/journald.conf
    rsyslogPrepareConf
    rsyslogConfigIsNewSyntax || rsyslogConfigAddTo --begin "RULES" /etc/rsyslog.conf <<EOF
# ompipe test rule
\$SystemLogRateLimitInterval 0
\$SystemLogRateLimitBurst 0

\$ActionQueueFileName pipeRule1
\$ActionQueueMaxDiskSpace 1g  
\$ActionQueueSaveOnShutdown on 
\$ActionQueueType LinkedList   
\$ActionResumeRetryCount -1 
local6.info    |/var/log/rsyslog.test.pipe
EOF

    rsyslogConfigIsNewSyntax && rsyslogConfigAddTo --begin "RULES" /etc/rsyslog.conf <<EOF
# ompipe test rule
\$SystemLogRateLimitInterval 0
\$SystemLogRateLimitBurst 0

if (\$syslogfacility-text == 'local6' )
then {
    action(type="ompipe"
            queue.type="LinkedList"
            queue.FileName="pipe.queue"
            queue.MaxDiskSpace="1G"
            queue.SaveOnShutdown="on"
            action.resumeRetryCount="-1"

            pipe="/var/log/rsyslog.test.pipe"
            )
    stop
}
EOF

	rlRun "sed -i "s/#RateLimitInterval=30s/RateLimitInterval=0/g" /etc/systemd/journald.conf"
	rlRun "sed -i "s/#RateLimitBurst=1000/RateLimitBurst=0/g" /etc/systemd/journald.conf"
	rlRun "systemctl restart systemd-journald.service"

	rlRun "TMPFILE=\`mktemp\`"
        rlRun "mkfifo /var/log/rsyslog.test.pipe"
        rlRun "chcon --reference=/var/log/messages /var/log/rsyslog.test.pipe" 0 "Changing SElinux context on /var/log/rsyslog.test.pipe"
        rsyslogServiceStart
    rlPhaseEnd

    rlPhaseStartTest
	rlRun "bash ./genMessages.sh 2000"
	rlRun "sleep 3"
	rlRun "cat /var/log/rsyslog.test.pipe > $TMPFILE &" 0 "Start reading from a pipe"

	COUNTER=0
	while true; do
		
		RESULT=`wc -l $TMPFILE | cut -d" " -f1`
		echo "Sent 2000, Got $RESULT"

		if [ "$RESULT" -eq "2000" ]; then
			rlRun "echo \"Sent 2000, Got $RESULT\" && true"
			rlRun "echo 'Got Everything!'"
			break
		fi
		
		if [ "$COUNTER" -eq "60" ]; then # timeout 1minute
			rlRun "echo \"Sent 2000, Got $RESULT\" && false"
			rlRun "echo 'Timeouted.' && false" 
			break
		fi

		sleep 1
		COUNTER=$(( $COUNTER + 1 ))
	done

        rsyslogServiceStop
	
    rlPhaseEnd

    rlPhaseStartCleanup
        rlFileRestore
        rlRun "rm -f /var/log/rsyslog.test.pipe $TMPFILE"
        rsyslogServiceRestore
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
