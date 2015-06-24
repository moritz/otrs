#!/usr/bin/perl
# --
# Copyright (C) 2001-2015 OTRS AG, http://otrs.com/
# --
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU AFFERO General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA
# or see http://www.gnu.org/licenses/agpl.txt.
# --

use strict;
use warnings;

# use ../ as lib location
use File::Basename;
use FindBin qw($RealBin);
use lib dirname($RealBin);
use lib dirname($RealBin) . '/Kernel/cpan-lib';

use Getopt::Std qw();
use Kernel::Config;
use Kernel::System::ObjectManager;
use Kernel::System::SysConfig;
use Kernel::System::Cache;
use Kernel::System::VariableCheck qw(:all);

local $Kernel::OM = Kernel::System::ObjectManager->new(
    'Kernel::System::Log' => {
        LogPrefix => 'OTRS-DBUpdate-to-5.pl',
    },
);

{

    # get options
    my %Opts;
    Getopt::Std::getopt( 'h', \%Opts );

    if ( exists $Opts{h} ) {
        print <<"EOF";

DBUpdate-to-5.pl - Upgrade script for OTRS 4 to 5 migration.
Copyright (C) 2001-2015 OTRS AG, http://otrs.com/

Usage: $0 [-h]
    Options are as follows:
        -h      display this help

EOF
        exit 1;
    }

    # UID check if not on Windows
    if ( $^O ne 'MSWin32' && $> == 0 ) {    # $EFFECTIVE_USER_ID
        die "
Cannot run this program as root.
Please run it as the 'otrs' user or with the help of su:
    su -c \"$0\" -s /bin/bash otrs
";
    }

    # enable auto-flushing of STDOUT
    $| = 1;                                 ## no critic

    # define tasks and their messages
    my @Tasks = (
        {
            Message => 'Refresh configuration cache',
            Command => \&RebuildConfig,
        },
        {
            Message => 'Check framework version',
            Command => \&_CheckFrameworkVersion,
        },
        {
            Message => 'Migrate charset to UTF-8 on auto_response table',
            Command => \&_MigrateCharsetAndDeleteCharsetColumnsAutoResponse,
        },
        {
            Message => 'Migrate charset to UTF-8 on notification_event table',
            Command => \&_MigrateCharsetAndDeleteCharsetColumnsNotificationEvent,
        },
        {
            Message => 'Migrate event based notifications to support multiple languages',
            Command => \&_MigrateEventNotificationsToMultiLanguage,
        },
        {
            Message => 'Migrate notifications to event based notifications',
            Command => \&_MigrateNotifications,
        },
        {
            Message => 'Migrate send notification user preferences',
            Command => \&_MigrateSettings,
        },
        {
            Message => 'Migrate Output configurations to the new module locations',
            Command => \&_MigrateConfigs,
        },
        {
            Message => 'Clean up the cache',
            Command => sub {
                $Kernel::OM->Get('Kernel::System::Cache')->CleanUp();
            },
        },
        {
            Message => 'Refresh configuration cache another time',
            Command => \&RebuildConfig,
        },
    );

    print "\nMigration started...\n\n";

    # get the number of total steps
    my $Steps = scalar @Tasks;
    my $Step  = 1;
    for my $Task (@Tasks) {

        # show task message
        print "Step $Step of $Steps: $Task->{Message}...";

        # run task command
        if ( &{ $Task->{Command} } ) {
            print "done.\n\n";
        }
        else {
            print "error.\n\n";
            die;
        }

        $Step++;
    }

    print "Migration completed!\n";

    exit 0;
}

=item RebuildConfig()

refreshes the configuration to make sure that a ZZZAAuto.pm is present
after the upgrade.

    RebuildConfig();

=cut

sub RebuildConfig {

    my $SysConfigObject = Kernel::System::SysConfig->new();

    # Rebuild ZZZAAuto.pm with current values
    if ( !$SysConfigObject->WriteDefault() ) {
        die "Error: Can't write default config files!";
    }

    # Force a reload of ZZZAuto.pm and ZZZAAuto.pm to get the new values
    for my $Module ( sort keys %INC ) {
        if ( $Module =~ m/ZZZAA?uto\.pm$/ ) {
            delete $INC{$Module};
        }
    }

    # reload config object
    print "\nIf you see warnings about 'Subroutine Load redefined', that's fine, no need to worry!\n";

    # create common objects with new default config
    $Kernel::OM->ObjectsDiscard();

    return 1;
}

=item _CheckFrameworkVersion()

Check if framework it's the correct one for Dynamic Fields migration.

    _CheckFrameworkVersion();

=cut

sub _CheckFrameworkVersion {
    my $Home = $Kernel::OM->Get('Kernel::Config')->Get('Home');

    # load RELEASE file
    if ( -e !"$Home/RELEASE" ) {
        die "Error: $Home/RELEASE does not exist!";
    }
    my $ProductName;
    my $Version;
    if ( open( my $Product, '<', "$Home/RELEASE" ) ) {    ## no critic
        while (<$Product>) {

            # filtering of comment lines
            if ( $_ !~ /^#/ ) {
                if ( $_ =~ /^PRODUCT\s{0,2}=\s{0,2}(.*)\s{0,2}$/i ) {
                    $ProductName = $1;
                }
                elsif ( $_ =~ /^VERSION\s{0,2}=\s{0,2}(.*)\s{0,2}$/i ) {
                    $Version = $1;
                }
            }
        }
        close($Product);
    }
    else {
        die "Error: Can't read $Home/RELEASE: $!";
    }

    if ( $ProductName ne 'OTRS' ) {
        die "Error: No OTRS system found"
    }
    if ( $Version !~ /^5\.0(.*)$/ ) {

        die "Error: You are trying to run this script on the wrong framework version $Version!"
    }

    return 1;
}

=item _MigrateCharsetAndDeleteCharsetColumnsAutoResponse()

Migrate the charset of the auto_response table and the notification_event table to UTF-8 and delete the charset columns.

    _MigrateCharsetAndDeleteCharsetColumnsAutoResponse();

=cut

sub _MigrateCharsetAndDeleteCharsetColumnsAutoResponse {

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    my $ErrorOutput;
    my $CharsetIsPresent = 1;

    # use do for restoring STDERR
    do {
        local *STDERR;
        open STDERR, '>:utf8', \$ErrorOutput;    ## no critic

        # sanity check to verify the charset column is present
        $CharsetIsPresent = $DBObject->Prepare(
            SQL => 'SELECT charset FROM auto_response',
        );
    };

    return 1 if !$CharsetIsPresent;

    # read auto_response table
    return if !$DBObject->Prepare(
        SQL => 'SELECT id, text0, text1, charset FROM auto_response',
    );

    # get encode object
    my $EncodeObject = $Kernel::OM->Get('Kernel::System::Encode');

    # read the auto responses and store in array
    my @AutoResponses;
    ROW:
    while ( my @Row = $DBObject->FetchrowArray() ) {

        my %Data = (
            ID      => $Row[0],
            Text0   => $Row[1],
            Text1   => $Row[2],
            Charset => $Row[3],
        );

        # convert body
        $Data{Text0} = $EncodeObject->Convert(
            Text  => $Data{Text0},
            From  => $Data{Charset},
            To    => 'utf-8',
            Check => 1,
        );

        # convert subject
        $Data{Text1} = $EncodeObject->Convert(
            Text  => $Data{Text1},
            From  => $Data{Charset},
            To    => 'utf-8',
            Check => 1,
        );

        # skip if nothing was changed and charset column is already in utf-8
        if ( ( $Data{Text0} eq $Row[1] ) && ( $Data{Text1} eq $Row[2] ) && ( $Data{Charset} eq 'utf-8' ) ) {
            next ROW;
        }

        # update charset column to utf-8
        $Data{Charset} = 'utf-8';

        push @AutoResponses, \%Data;
    }

    # write converted responses back to database
    for my $AutoResponse (@AutoResponses) {

        # update the database
        return if !$DBObject->Do(
            SQL  => 'UPDATE auto_response SET text0 = ?, text1 = ?, charset = ? WHERE id = ?',
            Bind => [
                \$AutoResponse->{Text0},
                \$AutoResponse->{Text1},
                \$AutoResponse->{Charset},
                \$AutoResponse->{ID},
            ],
        );
    }

    # drop charset column from auto_response table
    my $XMLString = '
        <TableAlter Name="auto_response">
            <ColumnDrop Name="charset"/>
        </TableAlter>';

    my @SQL;
    my @SQLPost;

    my $XMLObject = $Kernel::OM->Get('Kernel::System::XML');

    # create database specific SQL and PostSQL commands
    my @XMLARRAY = $XMLObject->XMLParse( String => $XMLString );

    # create database specific SQL
    push @SQL, $DBObject->SQLProcessor(
        Database => \@XMLARRAY,
    );

    # create database specific PostSQL
    push @SQLPost, $DBObject->SQLProcessorPost();

    # execute SQL
    for my $SQL ( @SQL, @SQLPost ) {
        my $Success = $DBObject->Do( SQL => $SQL );
        if ( !$Success ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Error during execution of '$SQL'!",
            );
            return;
        }
    }

    return 1;
}

=item _MigrateCharsetAndDeleteCharsetColumnsNotificationEvent()

Migrate the charset of the auto_response table and the notification_event table to UTF-8 and delete the charset columns.

    _MigrateCharsetAndDeleteCharsetColumnsNotificationEvent();

=cut

sub _MigrateCharsetAndDeleteCharsetColumnsNotificationEvent {

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    my $ErrorOutput;
    my $CharsetIsPresent = 1;

    # use do for restoring STDERR
    do {
        local *STDERR;
        open STDERR, '>:utf8', \$ErrorOutput;    ## no critic

        # sanity check to verify the charset column is present
        $CharsetIsPresent = $DBObject->Prepare(
            SQL => 'SELECT charset FROM notification_event',
        );
    };
    return 1 if !$CharsetIsPresent;

    # get encode object
    my $EncodeObject = $Kernel::OM->Get('Kernel::System::Encode');

    # read notification_event
    return if !$DBObject->Prepare(
        SQL => 'SELECT id, subject, text, charset FROM notification_event',
    );

    # read the notification_event entries and store in array
    my @NotificationsEvent;
    ROW:
    while ( my @Row = $DBObject->FetchrowArray() ) {

        my %Data = (
            ID      => $Row[0],
            Subject => $Row[1],
            Body    => $Row[2],
            Charset => $Row[3],
        );

        # convert subject
        $Data{Subject} = $EncodeObject->Convert(
            Text  => $Data{Subject},
            From  => $Data{Charset},
            To    => 'utf-8',
            Check => 1,
        );

        # convert body
        $Data{Body} = $EncodeObject->Convert(
            Text  => $Data{Body},
            From  => $Data{Charset},
            To    => 'utf-8',
            Check => 1,
        );

        # skip if nothing was changed and charset column is already in utf-8
        if ( ( $Data{Subject} eq $Row[1] ) && ( $Data{Body} eq $Row[2] ) && ( $Data{Charset} eq 'utf-8' ) ) {
            next ROW;
        }

        # update Charset column to utf-8
        $Data{Charset} = 'utf-8';

        push @NotificationsEvent, \%Data;
    }

    # write converted event notifications back to database
    for my $Notification (@NotificationsEvent) {

        # update the database
        return if !$DBObject->Do(
            SQL  => 'UPDATE notification_event SET subject = ?, text = ?, charset = ? WHERE id = ?',
            Bind => [
                \$Notification->{Subject},
                \$Notification->{Body},
                \$Notification->{Charset},
                \$Notification->{ID},
            ],
        );
    }

    # drop charset column from notification_event table
    my $XMLString = '
        <TableAlter Name="notification_event">
            <ColumnDrop Name="charset"/>
        </TableAlter>';

    my @SQL;
    my @SQLPost;

    my $XMLObject = $Kernel::OM->Get('Kernel::System::XML');

    # create database specific SQL and PostSQL commands
    my @XMLARRAY = $XMLObject->XMLParse( String => $XMLString );

    # create database specific SQL
    push @SQL, $DBObject->SQLProcessor(
        Database => \@XMLARRAY,
    );

    # create database specific PostSQL
    push @SQLPost, $DBObject->SQLProcessorPost();

    # execute SQL
    for my $SQL ( @SQL, @SQLPost ) {
        my $Success = $DBObject->Do( SQL => $SQL );
        if ( !$Success ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Error during execution of '$SQL'!",
            );
            return;
        }
    }

    return 1;
}

=item _MigrateEventNotificationsToMultiLanguage()

Migrate event based notifications to support multiple languages.

    _MigrateEventNotificationsToMultiLanguage();

=cut

sub _MigrateEventNotificationsToMultiLanguage {

    # get needed objects
    my $DBObject                = $Kernel::OM->Get('Kernel::System::DB');
    my $NotificationEventObject = $Kernel::OM->Get('Kernel::System::NotificationEvent');

    my $ErrorOutput;
    my $ColumnsArePresent = 1;

    # use do for restoring STDERR
    do {
        local *STDERR;
        open STDERR, '>:utf8', \$ErrorOutput;    ## no critic

        # sanity check to verify the subject, text and content_type columns are present
        $ColumnsArePresent = $DBObject->Prepare(
            SQL => 'SELECT subject, text, content_type FROM notification_event',
        );
    };
    return 1 if !$ColumnsArePresent;

    # get the systems default language
    my $Language = $Kernel::OM->Get('Kernel::Config')->Get('DefaultLanguage') || 'en';

    return if !$DBObject->Prepare(
        SQL => 'SELECT id, name, subject, text, content_type, valid_id, comments
            FROM notification_event',
    );

    # read the notification_event entries and store in array
    my @NotificationsEvent;
    ROW:
    while ( my @Row = $DBObject->FetchrowArray() ) {

        if ( !$Row[2] || !$Row[3] || !$Row[4] ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Notification: $Row[1] is invalid and will not be migrated, or was migrated previously.",
            );
            next ROW;
        }

        my %Data = (
            ID      => $Row[0],
            Name    => $Row[1],
            Message => {
                $Language => {
                    Subject     => $Row[2],
                    Body        => $Row[3],
                    ContentType => $Row[4],
                },
            },
            ValidID => $Row[5],
            Comment => $Row[6],
        );

        push @NotificationsEvent, \%Data;
    }

    # read notification event item data
    for my $Notification (@NotificationsEvent) {

        $DBObject->Prepare(
            SQL => 'SELECT event_key, event_value
                FROM notification_event_item
                WHERE notification_id = ?',
            Bind => [ \$Notification->{ID} ],
        );

        while ( my @Row = $DBObject->FetchrowArray() ) {
            push @{ $Notification->{Data}->{ $Row[0] } }, $Row[1];
        }
    }

    # update notifications
    for my $Notification (@NotificationsEvent) {

        # update
        my $Success = $NotificationEventObject->NotificationUpdate(
            %{$Notification},
            UserID => 1,
        );

        # error handling
        return if !$Success;
    }

    # drop migrated columns from notification_event table
    my $XMLString = '
        <TableAlter Name="notification_event">
            <ColumnDrop Name="subject"/>
            <ColumnDrop Name="text"/>
            <ColumnDrop Name="content_type"/>
        </TableAlter>';

    my @SQL;
    my @SQLPost;

    my $XMLObject = $Kernel::OM->Get('Kernel::System::XML');

    # create database specific SQL and PostSQL commands
    my @XMLARRAY = $XMLObject->XMLParse( String => $XMLString );

    # create database specific SQL
    push @SQL, $DBObject->SQLProcessor(
        Database => \@XMLARRAY,
    );

    # create database specific PostSQL
    push @SQLPost, $DBObject->SQLProcessorPost();

    # execute SQL
    for my $SQL ( @SQL, @SQLPost ) {
        my $Success = $DBObject->Do( SQL => $SQL );
        if ( !$Success ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Error during execution of '$SQL'!",
            );
            return;
        }
    }

    return 1;
}

=item _MigrateNotifications()

Migrate notifications to event based notifications.

    _MigrateNotifications();

=cut

sub _MigrateNotifications {

    # get needed objects
    my $DBObject                = $Kernel::OM->Get('Kernel::System::DB');
    my $EncodeObject            = $Kernel::OM->Get('Kernel::System::Encode');
    my $NotificationEventObject = $Kernel::OM->Get('Kernel::System::NotificationEvent');
    my $ConfigObject            = $Kernel::OM->Get('Kernel::Config');

    my $ErrorOutput;
    my $NotificationsTableIsPresent = 1;

    # use do for restoring STDERR
    do {
        local *STDERR;
        open STDERR, '>:utf8', \$ErrorOutput;    ## no critic

        # sanity check to verify the subject, text and content_type columns are present
        $NotificationsTableIsPresent = $DBObject->Prepare(
            SQL => 'SELECT notification_type FROM notifications',
        );
    };
    return 1 if !$NotificationsTableIsPresent;

    # get valid list
    my %ValidList        = $Kernel::OM->Get('Kernel::System::Valid')->ValidList();
    my %ValidListReverse = reverse %ValidList;

    my %NotificationList        = $NotificationEventObject->NotificationList();
    my %NotificationListReverse = reverse %NotificationList;

    # mapping array based on notification type
    my %NotificationTypeMapping = (
        'Agent::NewTicket' => [
            {
                Name                   => 'New ticket created',
                VisibleForAgent        => [1],
                VisibleForAgentTooltip => [
                    'You will receive a notification each time a new ticket is created in one of your "My Queues" or "My Services".'
                ],
                Events     => ['NotificationNewTicket'],
                Recipients => [ 'AgentMyQueues', 'AgentMyServices' ],
                Transports => ['Email'],
            },
        ],
        'Agent::FollowUp' => [
            {
                Name                   => 'Follow-up on an unlocked ticket',
                VisibleForAgent        => [1],
                VisibleForAgentTooltip => [
                    'You will receive a notification if a customer sends a follow up to an unlocked ticket which is in your "My Queues" or "My Services".'
                ],
                Events     => ['NotificationFollowUp'],
                Recipients => [ 'AgentOwner', 'AgentWatcher', 'AgentMyQueues', 'AgentMyServices' ],
                LockID     => [1],                                                                    # unlocked
                Transports => ['Email'],
            },
            {
                Name                   => 'Follow-up on a locked ticket',
                VisibleForAgent        => [1],
                VisibleForAgentTooltip => [
                    'You will receive a notification if a customer sends a follow up to a locked ticket of which you are the ticket owner or responsible.'
                ],
                Events     => ['NotificationFollowUp'],
                Recipients => [ 'AgentOwner', 'AgentResponsible', 'AgentWatcher' ],
                LockID     => [2],                                                                    # locked
                Transports => ['Email'],
            },
        ],
        'Agent::LockTimeout' => [
            {
                Name            => 'Automatic ticket unlock',
                VisibleForAgent => [1],
                VisibleForAgentTooltip =>
                    ['You will receive a notification as soon as a ticket owned by you is automatically unlocked.'],
                Events     => ['NotificationLockTimeout'],
                Recipients => ['AgentOwner'],
                Transports => ['Email'],
            },
        ],
        'Agent::OwnerUpdate' => [
            {
                Name       => 'Ticket owner update',
                Events     => ['NotificationOwnerUpdate'],
                Recipients => ['AgentOwner'],
                Transports => ['Email'],
            },
        ],
        'Agent::ResponsibleUpdate' => [
            {
                Name       => 'Ticket responsible update',
                Events     => ['NotificationResponsibleUpdate'],
                Recipients => ['AgentResponsible'],
                Transports => ['Email'],
            },
        ],
        'Agent::AddNote' => [
            {
                Name       => 'Note added to ticket',
                Events     => ['NotificationAddNote'],
                Recipients => [ 'AgentOwner', 'AgentResponsible', 'AgentWatcher' ],
                Transports => ['Email'],
            },
        ],
        'Agent::Move' => [
            {
                Name            => 'Ticket moved',
                VisibleForAgent => [1],
                VisibleForAgentTooltip =>
                    ['You will receive a notification if a ticket is moved into one of your "My Queues".'],
                Events     => ['NotificationMove'],
                Recipients => ['AgentMyQueues'],
                Transports => ['Email'],
            },
        ],
        'Agent::PendingReminder' => [
            {
                Name       => 'Reminder time passed for a locked ticket',
                Events     => ['NotificationPendingReminder'],
                Recipients => [ 'AgentOwner', 'AgentResponsible' ],
                OncePerDay => [1],
                LockID     => [2],                                          # locked
                Transports => ['Email'],
            },
            {
                Name       => 'Reminder time passed for an unlocked ticket',
                Events     => ['NotificationPendingReminder'],
                Recipients => [ 'AgentOwner', 'AgentResponsible', 'AgentMyQueues' ],
                OncePerDay => [1],
                LockID     => [1],                                                     # unlocked
                Transports => ['Email'],
            },
        ],
        'Agent::Escalation' => [
            {
                Name       => 'Ticket has escalated',
                Events     => ['NotificationEscalation'],
                Recipients => [ 'AgentMyQueues', 'AgentWritePermissions' ],
                OncePerDay => [1],
                Transports => ['Email'],
            },
        ],
        'Agent::EscalationNotifyBefore' => [
            {
                Name       => 'Ticket will soon escalate',
                Events     => ['NotificationEscalationNotifyBefore'],
                Recipients => [ 'AgentMyQueues', 'AgentWritePermissions' ],
                OncePerDay => [1],
                Transports => ['Email'],
            },
        ],
        'Agent::ServiceUpdate' => [
            {
                Name                   => 'Ticket service update',
                VisibleForAgent        => [1],
                VisibleForAgentTooltip => [
                    'You will receive a notification if a ticket\'s service is changed to one of your "My Services".'
                ],
                Events     => ['NotificationServiceUpdate'],
                Recipients => ['AgentMyServices'],
                Transports => ['Email'],
            },
        ],
    );

    # for all standard otrs notification types included in the framework
    NOTIFICATIONTYPE:
    for my $NotificationType ( sort keys %NotificationTypeMapping ) {

        # read notifications for this notification type
        return if !$DBObject->Prepare(
            SQL => 'SELECT notification_type, notification_charset,
                notification_language, subject, text, content_type
                FROM notifications
                WHERE notification_type = ?',
            Bind => [ \$NotificationType ],
        );

        my %Message;
        while ( my @Row = $DBObject->FetchrowArray() ) {

            my %Data = (
                NotificationType => $Row[0],
                Charset          => $Row[1],
                Language         => $Row[2],
                Subject          => $Row[3],
                Body             => $Row[4],
                ContentType      => $Row[5],
            );

            # convert subject
            $Data{Subject} = $EncodeObject->Convert(
                Text  => $Data{Subject},
                From  => $Data{Charset},
                To    => 'utf-8',
                Check => 1,
            );

            # convert body
            $Data{Body} = $EncodeObject->Convert(
                Text  => $Data{Body},
                From  => $Data{Charset},
                To    => 'utf-8',
                Check => 1,
            );

            # store each language data
            $Message{ $Data{Language} } = {
                Subject     => $Data{Subject},
                Body        => $Data{Body},
                ContentType => $Data{ContentType},
            };
        }

        for my $NotificationData ( @{ $NotificationTypeMapping{$NotificationType} } ) {

            my $NotificationName = $NotificationData->{Name};
            delete $NotificationData->{Name};

            # check for special settings on system
            if (
                $NotificationType eq 'Agent::PendingReminder'
                && $ConfigObject->Get('Ticket::PendingNotificationNotToResponsible')
                )
            {
                if ( $NotificationName eq 'Reminder time passed for a locked ticket' ) {
                    $NotificationData->{Recipients} = ['AgentOwner'];
                }
                elsif ( $NotificationName eq 'Reminder time passed for an unlocked ticket' ) {
                    $NotificationData->{Recipients} = [ 'AgentOwner', 'AgentMyQueues' ];
                }
            }
            elsif (
                $NotificationType eq 'Agent::FollowUp'
                && $ConfigObject->Get('PostmasterFollowUpOnUnlockAgentNotifyOnlyToOwner')
                && $NotificationName eq 'Follow-up on an unlocked ticket'
                )
            {
                $NotificationData->{Recipients} = ['AgentOwner'];
            }

            next NOTIFICATIONTYPE if $NotificationListReverse{$NotificationName};

            # add new event notification
            my $ID = $NotificationEventObject->NotificationAdd(
                Name    => 'Old ' . $NotificationName,
                Data    => $NotificationData,
                Message => \%Message,
                Comment => '',
                ValidID => $ValidListReverse{invalid},
                UserID  => 1,
            );

            # put the suffix back
            $NotificationData->{Name} = $NotificationName;

            # error handling
            return if !$ID;
        }
    }

    # delete old notifications from notification table
    for my $NotificationType ( sort keys %NotificationTypeMapping ) {

        return if !$DBObject->Do(
            SQL  => 'DELETE FROM notifications WHERE notification_type = ?',
            Bind => [ \$NotificationType ],
        );
    }

    # get number of remaining entries
    return if !$DBObject->Prepare(
        SQL => 'SELECT COUNT(id) FROM notifications',
    );

    my $Count;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Count = $Row[0];
    }

    # delete table but only if table is empty
    # if there are some entries left, these must be deleted by other modules
    # so we give them a chance to be migrated from these modules
    if ( !$Count ) {

        # drop table 'notifications'
        my $XMLString = '<TableDrop Name="notifications"/>';

        my @SQL;
        my @SQLPost;

        my $XMLObject = $Kernel::OM->Get('Kernel::System::XML');

        # create database specific SQL and PostSQL commands
        my @XMLARRAY = $XMLObject->XMLParse( String => $XMLString );

        # create database specific SQL
        push @SQL, $DBObject->SQLProcessor(
            Database => \@XMLARRAY,
        );

        # create database specific PostSQL
        push @SQLPost, $DBObject->SQLProcessorPost();

        # execute SQL
        for my $SQL ( @SQL, @SQLPost ) {
            my $Success = $DBObject->Do( SQL => $SQL );
            if ( !$Success ) {
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'error',
                    Message  => "Error during execution of '$SQL'!",
                );
                return;
            }
        }
    }

    # insert new and valid notifications
    my %NotificationLanguages = _NewAgentNotificationsLanguageGet();

    # for all standard otrs notification types included in the framework
    NEWNOTIFICATION:
    for my $NotificationType ( sort keys %NotificationTypeMapping ) {

        my %Message = %{ $NotificationLanguages{$NotificationType} };

        for my $NotificationData ( @{ $NotificationTypeMapping{$NotificationType} } ) {

            my $NotificationName = $NotificationData->{Name};
            delete $NotificationData->{Name};

            next NEWNOTIFICATION if $NotificationListReverse{$NotificationName};

            # add new event notification
            my $ID = $NotificationEventObject->NotificationAdd(
                Name    => $NotificationName,
                Data    => $NotificationData,
                Message => \%Message,
                Comment => '',
                ValidID => $ValidListReverse{valid},
                UserID  => 1,
            );

            # error handling
            return if !$ID;
        }
    }

    return 1;
}

=item _MigrateConfigs()

Change tool-bar configurations to match the new module location.

    _MigrateConfigs();

=cut

sub _MigrateConfigs {

    # get needed objects
    my $ConfigObject    = $Kernel::OM->Get('Kernel::Config');
    my $SysConfigObject = $Kernel::OM->Get('Kernel::System::SysConfig');

    print "\n--- Toolbar modules...";

    # Toolbar Modules
    my $Setting = $ConfigObject->Get('Frontend::ToolBarModule');

    TOOLBARMODULE:
    for my $ToolbarModule ( sort keys %{$Setting} ) {

        # update module location
        my $Module = $Setting->{$ToolbarModule}->{'Module'};
        if ( $Module !~ m{Kernel::Output::HTML::ToolBar(\w+)} ) {
            next TOOLBARMODULE;
        }

        $Module =~ s{Kernel::Output::HTML::ToolBar(\w+)}{Kernel::Output::HTML::ToolBar::$1}xmsg;
        $Setting->{$ToolbarModule}->{'Module'} = $Module;

        # set new setting,
        my $Success = $SysConfigObject->ConfigItemUpdate(
            Valid => 1,
            Key   => 'Frontend::ToolBarModule###' . $ToolbarModule,
            Value => $Setting->{$ToolbarModule},
        );
    }

    print "...done.\n";
    print "--- Ticket menu modules...";

    # Ticket Menu Modules
    $Setting = $ConfigObject->Get('Ticket::Frontend::MenuModule');

    MENUMODULE:
    for my $MenuModule ( sort keys %{$Setting} ) {

        # update module location
        my $Module = $Setting->{$MenuModule}->{'Module'};
        if ( $Module !~ m{Kernel::Output::HTML::TicketMenu(\w+)} ) {
            next MENUMODULE;
        }

        $Module =~ s{Kernel::Output::HTML::TicketMenu(\w+)}{Kernel::Output::HTML::TicketMenu::$1}xmsg;
        $Setting->{$MenuModule}->{'Module'} = $Module;

        # set new setting,
        my $Success = $SysConfigObject->ConfigItemUpdate(
            Valid => 1,
            Key   => 'Ticket::Frontend::MenuModule###' . $MenuModule,
            Value => $Setting->{$MenuModule},
        );
    }

    print "...done.\n";
    print "--- Ticket overview menu modules...";

    # Ticket Menu Modules
    $Setting = $ConfigObject->Get('Ticket::Frontend::OverviewMenuModule');

    MENUMODULE:
    for my $MenuModule ( sort keys %{$Setting} ) {

        # update module location
        my $Module = $Setting->{$MenuModule}->{'Module'};
        if ( $Module !~ m{Kernel::Output::HTML::TicketOverviewMenu(\w+)} ) {
            next MENUMODULE;
        }

        $Module =~ s{Kernel::Output::HTML::TicketOverviewMenu(\w+)}{Kernel::Output::HTML::TicketOverviewMenu::$1}xmsg;
        $Setting->{$MenuModule}->{'Module'} = $Module;

        # set new setting,
        my $Success = $SysConfigObject->ConfigItemUpdate(
            Valid => 1,
            Key   => 'Ticket::Frontend::OverviewMenuModule###' . $MenuModule,
            Value => $Setting->{$MenuModule},
        );
    }

    print "...done.\n";
    print "--- Ticket overview modules...";

    # Ticket Menu Modules
    $Setting = $ConfigObject->Get('Ticket::Frontend::Overview');

    OVERVIEWMODULE:
    for my $OverviewModule ( sort keys %{$Setting} ) {

        # update module location
        my $Module = $Setting->{$OverviewModule}->{'Module'};
        if ( $Module !~ m{Kernel::Output::HTML::TicketOverview(\w+)} ) {
            next OVERVIEWMODULE;
        }

        $Module =~ s{Kernel::Output::HTML::TicketOverview(\w+)}{Kernel::Output::HTML::TicketOverview::$1}xmsg;
        $Setting->{$OverviewModule}->{'Module'} = $Module;

        # set new setting,
        my $Success = $SysConfigObject->ConfigItemUpdate(
            Valid => 1,
            Key   => 'Ticket::Frontend::Overview###' . $OverviewModule,
            Value => $Setting->{$OverviewModule},
        );
    }

    print "...done.\n";
    print "--- Preferences group modules...";

    # Preferences groups
    $Setting = $ConfigObject->Get('PreferencesGroups');

    PREFERENCEMODULE:
    for my $PreferenceModule ( sort keys %{$Setting} ) {

        # update module location
        my $Module = $Setting->{$PreferenceModule}->{'Module'};
        if ( $Module !~ m{Kernel::Output::HTML::Preferences(\w+)} ) {
            next PREFERENCEMODULE;
        }

        $Module =~ s{Kernel::Output::HTML::Preferences(\w+)}{Kernel::Output::HTML::Preferences::$1}xmsg;
        $Setting->{$PreferenceModule}->{'Module'} = $Module;

        # set new setting,
        my $Success = $SysConfigObject->ConfigItemUpdate(
            Valid => 1,
            Key   => 'PreferencesGroups###' . $PreferenceModule,
            Value => $Setting->{$PreferenceModule},
        );
    }

    print "...done.\n";
    print "--- SLA/Service/Queue preference modules...";

    # SLA, Service and Queue preferences
    for my $Type (qw(SLA Service Queue)) {

        $Setting = $ConfigObject->Get( $Type . 'Preferences' );

        MODULE:
        for my $PreferenceModule ( sort keys %{$Setting} ) {

            # update module location
            my $Module = $Setting->{$PreferenceModule}->{'Module'};
            my $Regex  = 'Kernel::Output::HTML::' . $Type . 'Preferences(\w+)';
            if ( $Module !~ m{$Regex} ) {
                next MODULE;
            }

            $Module =~ s{$Regex}{Kernel::Output::HTML::${Type}Preferences::$1}xmsg;
            $Setting->{$PreferenceModule}->{'Module'} = $Module;

            # set new setting,
            my $Success = $SysConfigObject->ConfigItemUpdate(
                Valid => 1,
                Key   => $Type . 'Preferences###' . $PreferenceModule,
                Value => $Setting->{$PreferenceModule},
            );
        }
    }

    print "...done.\n";
    print "--- Article pre view modules...";

    # Article pre view modules
    $Setting = $ConfigObject->Get('Ticket::Frontend::ArticlePreViewModule');

    ARTICLEMODULE:
    for my $ArticlePreViewModule ( sort keys %{$Setting} ) {

        # update module location
        my $Module = $Setting->{$ArticlePreViewModule}->{'Module'};
        if ( $Module !~ m{Kernel::Output::HTML::ArticleCheck(\w+)} ) {
            next ARTICLEMODULE;
        }

        $Module =~ s{Kernel::Output::HTML::ArticleCheck(\w+)}{Kernel::Output::HTML::ArticleCheck::$1}xmsg;
        $Setting->{$ArticlePreViewModule}->{'Module'} = $Module;

        # set new setting,
        my $Success = $SysConfigObject->ConfigItemUpdate(
            Valid => 1,
            Key   => 'Ticket::Frontend::ArticlePreViewModule###' . $ArticlePreViewModule,
            Value => $Setting->{$ArticlePreViewModule},
        );
    }

    print "...done.\n";
    print "--- NavBar menu modules...";

    # NavBar menu modules
    my @NavBarTypes = (
        {
            Path => 'Frontend::NavBarModule',
        },
        {
            Path => 'CustomerFrontend::NavBarModule',
        },
    );

    for my $Type (@NavBarTypes) {

        $Setting = $ConfigObject->Get( $Type->{Path} );

        NAVBARMODULE:
        for my $NavBarModule ( sort keys %{$Setting} ) {

            # update module location
            my $Module = $Setting->{$NavBarModule}->{'Module'};

            if ( $Module !~ m{Kernel::Output::HTML::NavBar(\w+)} ) {
                next NAVBARMODULE;
            }

            $Module =~ s{Kernel::Output::HTML::NavBar(\w+)}{Kernel::Output::HTML::NavBar::$1}xmsg;
            $Setting->{$NavBarModule}->{'Module'} = $Module;

            # set new setting,
            my $Success = $SysConfigObject->ConfigItemUpdate(
                Valid => 1,
                Key   => $Type->{Path} . '###' . $NavBarModule,
                Value => $Setting->{$NavBarModule},
            );
        }
    }

    print "...done.\n";
    print "--- NavBar ModuleAdmin modules...";

    # NavBar module admin
    $Setting = $ConfigObject->Get('Frontend::Module');

    MODULEADMIN:
    for my $ModuleAdmin ( sort keys %{$Setting} ) {

        # update module location
        my $Module = $Setting->{$ModuleAdmin}->{NavBarModule}->{'Module'} // '';

        if ( $Module !~ m{Kernel::Output::HTML::NavBar(\w+)} ) {
            next MODULEADMIN;
        }
        $Setting->{$ModuleAdmin}->{NavBarModule}->{'Module'} = "Kernel::Output::HTML::NavBar::ModuleAdmin";

        # set new setting,
        my $Success = $SysConfigObject->ConfigItemUpdate(
            Valid => 1,
            Key   => 'Frontend::Module###' . $ModuleAdmin,
            Value => $Setting->{$ModuleAdmin},
        );
    }

    print "...done.\n";
    print "--- Dashboard modules...";

    # Dashboard modules
    my @DashboardTypes = (
        {
            Path => 'DashboardBackend',
        },
        {
            Path => 'AgentCustomerInformationCenter::Backend',
        },
    );

    for my $Type (@DashboardTypes) {

        $Setting = $ConfigObject->Get( $Type->{Path} );

        DASHBOARDMODULE:
        for my $DashboardModule ( sort keys %{$Setting} ) {

            # update module location
            my $Module = $Setting->{$DashboardModule}->{'Module'} // '';

            if ( $Module !~ m{Kernel::Output::HTML::Dashboard(\w+)} ) {
                next DASHBOARDMODULE;
            }
            $Module =~ s{Kernel::Output::HTML::Dashboard(\w+)}{Kernel::Output::HTML::Dashboard::$1}xmsg;
            $Setting->{$DashboardModule}->{'Module'} = $Module;

            # set new setting,
            my $Success = $SysConfigObject->ConfigItemUpdate(
                Valid => 1,
                Key   => $Type->{Path} . '###' . $DashboardModule,
                Value => $Setting->{$DashboardModule},
            );
        }
    }

    print "...done.\n";
    print "--- Customer user generic modules...";

    # customer user generic module
    $Setting = $ConfigObject->Get('Frontend::CustomerUser::Item');

    CUSTOMERUSERGENERICMODULE:
    for my $CustomerUserGenericModule ( sort keys %{$Setting} ) {

        # update module location
        my $Module = $Setting->{$CustomerUserGenericModule}->{'Module'} // '';

        if ( $Module !~ m{Kernel::Output::HTML::CustomerUser(\w+)} ) {
            next CUSTOMERUSERGENERICMODULE;
        }
        $Module =~ s{Kernel::Output::HTML::CustomerUser(\w+)}{Kernel::Output::HTML::CustomerUser::$1}xmsg;
        $Setting->{$CustomerUserGenericModule}->{'Module'} = $Module;

        # set new setting,
        my $Success = $SysConfigObject->ConfigItemUpdate(
            Valid => 1,
            Key   => 'Frontend::CustomerUser::Item###' . $CustomerUserGenericModule,
            Value => $Setting->{$CustomerUserGenericModule},
        );
    }

    # set new setting for CustomerNewTicketQueueSelectionGeneric
    my $Success = $SysConfigObject->ConfigItemUpdate(
        Valid => 2,
        Key   => 'CustomerPanel::NewTicketQueueSelectionModule',
        Value => 'Kernel::Output::HTML::CustomerNewTicket::QueueSelectionGeneric',
    );

    print "...done.\n";
    print "--- FilterText modules...";

    # output filter module
    $Setting = $ConfigObject->Get('Frontend::Output::FilterText');

    FILTERTEXTMODULE:
    for my $FilterTextModule ( sort keys %{$Setting} ) {

        # update module location
        my $Module = $Setting->{$FilterTextModule}->{'Module'} // '';

        if ( $Module !~ m{Kernel::Output::HTML::OutputFilter::Text(\w+)} ) {
            next FILTERTEXTMODULE;
        }
        $Module =~ s{Kernel::Output::HTML::OutputFilter::Text(\w+)}{Kernel::Output::HTML::FilterText::$1}xmsg;
        $Setting->{$FilterTextModule}->{'Module'} = $Module;

        # set new setting,
        my $Success = $SysConfigObject->ConfigItemUpdate(
            Valid => 1,
            Key   => 'Frontend::Output::FilterText###' . $FilterTextModule,
            Value => $Setting->{$FilterTextModule},
        );
    }

    print "...done.\n";

    return 1;
}

=item _MigrateSettings()

Migrate different settings

    _MigrateSettings($CommonObject);

=cut

sub _MigrateSettings {

    # set transport name
    my $TransportName = 'Email';
    my $PreferenceKey = 'NotificationTransport';

    # get needed objects
    my $NotificationEventObject = $Kernel::OM->Get('Kernel::System::NotificationEvent');
    my $DBObject                = $Kernel::OM->Get('Kernel::System::DB');
    my $JSONObject              = $Kernel::OM->Get('Kernel::System::JSON');

    my %NotificationList = $NotificationEventObject->NotificationList();

    # get old preferences by user
    return if !$DBObject->Prepare(
        SQL => '
            SELECT user_id, preferences_key, preferences_value
            FROM user_preferences
            WHERE preferences_key LIKE(\'UserSend%\')
        ',
    );

    my %OldPreferences;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $OldPreferences{ $Row[0] }->{ $Row[1] } = $Row[2];
    }

    # create identifiers per each notification
    my %IdentifierList;
    NOTIFICATION:
    for my $NotificationID ( sort keys %NotificationList ) {
        next NOTIFICATION if !$NotificationList{$NotificationID};
        $IdentifierList{ $NotificationList{$NotificationID} } = "Notification-$NotificationID-$TransportName";
    }

    # set an OldPreference => NewNotification mapping
    my %NotificationsPreferencesMapping = (
        UserSendNewTicketNotification     => 'New ticket created',
        UserSendFollowUpNotification      => 'Follow-up on an unlocked ticket',
        UserSendLockTimeoutNotification   => 'Automatic ticket unlock',
        UserSendMoveNotification          => 'Ticket moved',
        UserSendServiceUpdateNotification => 'Ticket service update',
        UserSendWatcherNotification       => '',                                 #TODO: verify it this should be removed
    );

    # loop over each user
    for my $UserID ( sort keys %OldPreferences ) {

        my %UserNotificationTransport;

        # loop over the stored preferences per user
        PREFERENCE:
        for my $Preference ( sort keys %{ $OldPreferences{$UserID} } ) {

            next PREFERENCE if !$NotificationsPreferencesMapping{$Preference};

            my $PreferenceValue = 1;

            # just if the user explicitly says No Notification it will set to 0
            if ( defined $OldPreferences{$UserID}->{$Preference} && !$OldPreferences{$UserID}->{$Preference} ) {
                $PreferenceValue = 0;
            }

            # get key=>value pair for each notification
            my $NotificationName = $NotificationsPreferencesMapping{$Preference};
            my $Identifier       = $IdentifierList{$NotificationName};

            # set the value for the identifier
            $UserNotificationTransport{$Identifier} = $PreferenceValue;

            if ( $NotificationName eq 'Follow-up on an unlocked ticket' ) {

                $Identifier = $IdentifierList{'Follow-up on a locked ticket'};

                # set the value for the identifier
                $UserNotificationTransport{$Identifier} = $PreferenceValue;
            }
        }

        # encode data
        my $Value = $JSONObject->Encode(
            Data => \%UserNotificationTransport,
        );

        # do the update
        return if !$DBObject->Do(
            SQL => '
                INSERT INTO user_preferences
                (user_id, preferences_key, preferences_value)
                values ( ?, ?, ? )',
            Bind => [ \$UserID, \$PreferenceKey, \$Value ],
        );

    }

    # delete old UserSend preferences
    return if !$DBObject->Prepare(
        SQL => '
            DELETE FROM user_preferences
            WHERE preferences_key LIKE(\'UserSend%\')
        ',
    );

    return 1;
}

=item _NewAgentNotificationsLanguageGet()

Retrieve the languages for each notification.

    _NewAgentNotificationsLanguageGet();

=cut

sub _NewAgentNotificationsLanguageGet {

    # notification languages container
    my %NotificationLanguages = (
        'Agent::AddNote' => {
            'de' => {
                'Body' => 'Hallo <OTRS_UserFirstname> <OTRS_UserLastname>,

<OTRS_CURRENT_UserFirstname> <OTRS_CURRENT_UserLastname> fuegte eine Notiz an Ticket [<OTRS_TICKET_TicketNumber>].

Notiz:
<OTRS_CUSTOMER_BODY>

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>

Ihr OTRS Benachrichtigungs-Master',
                'ContentType' => 'text/plain',
                'Subject'     => 'Neue Notiz! (<OTRS_CUSTOMER_SUBJECT[24]>)'
            },
            'en' => {
                'Body' => 'Hi <OTRS_UserFirstname>,

<OTRS_CURRENT_UserFirstname> <OTRS_CURRENT_UserLastname> added a new note to ticket [<OTRS_TICKET_TicketNumber>].

Note:
<OTRS_CUSTOMER_BODY>

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>

Your OTRS Notification Master',
                'ContentType' => 'text/plain',
                'Subject'     => 'New note! (<OTRS_CUSTOMER_SUBJECT[24]>)'
            },
            'nl' => {
                'Body' => 'Beste <OTRS_UserFirstname>,

<OTRS_CURRENT_UserFirstname> <OTRS_CURRENT_UserLastname> heeft een nieuwe notitie toegevoegd aan [<OTRS_TICKET_TicketNumber>].

Notitie:
<OTRS_CUSTOMER_BODY>

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>
',
                'ContentType' => 'text/plain',
                'Subject'     => 'Nieuwe notitie (<OTRS_CUSTOMER_SUBJECT[24]>)'
                }
        },
        'Agent::Escalation' => {
            'de' => {
                'Body' => 'Hallo <OTRS_UserFirstname> <OTRS_UserLastname>,

das Ticket [<OTRS_TICKET_TicketNumber>] ist eskaliert!

Eskaliert am:   <OTRS_TICKET_EscalationDestinationDate>
Eskaliert seit: <OTRS_TICKET_EscalationDestinationIn>

<OTRS_CUSTOMER_FROM>

schrieb:
<snip>
<OTRS_CUSTOMER_EMAIL[30]>
<snip>

Bitte um Bearbeitung:

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>

Ihr OTRS Benachrichtigungs-Master',
                'ContentType' => 'text/plain',
                'Subject'     => 'Ticket Eskalation! (<OTRS_CUSTOMER_SUBJECT[24]>)'
            },
            'en' => {
                'Body' => 'Hi <OTRS_UserFirstname>,

The ticket [<OTRS_TICKET_TicketNumber>] is escalated!

Escalated at:    <OTRS_TICKET_EscalationDestinationDate>
Escalated since: <OTRS_TICKET_EscalationDestinationIn>

<OTRS_CUSTOMER_FROM>

wrote:
<snip>
<OTRS_CUSTOMER_EMAIL[30]>
<snip>

Please have a look at:

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>

Your OTRS Notification Master',
                'ContentType' => 'text/plain',
                'Subject'     => 'Ticket Escalation! (<OTRS_CUSTOMER_SUBJECT[24]>)'
            },
            'nl' => {
                'Body' => "Beste <OTRS_UserFirstname>,

Het ticket [<OTRS_TICKET_TicketNumber>] is geëscaleerd!

Geëscaleerd op:    <OTRS_TICKET_EscalationDestinationDate>
Geëscaleerd sinds: <OTRS_TICKET_EscalationDestinationIn>

<OTRS_CUSTOMER_FROM> schreef:

<OTRS_CUSTOMER_EMAIL[30]>
(eerste 30 regels zijn weergegeven)

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>
",
                'ContentType' => 'text/plain',
                'Subject'     => 'Escalatie (<OTRS_CUSTOMER_SUBJECT[24]>)'
                }
        },
        'Agent::EscalationNotifyBefore' => {
            'de' => {
                'Body' => 'Hallo <OTRS_UserFirstname> <OTRS_UserLastname>,

das Ticket [<OTRS_TICKET_TicketNumber>] wird bald eskalieren!

Eskalation um: <OTRS_TICKET_EscalationDestinationDate>
Eskalation in: <OTRS_TICKET_EscalationDestinationIn>

<OTRS_CUSTOMER_FROM>

schrieb:
<snip>
<OTRS_CUSTOMER_EMAIL[30]>
<snip>

Bitte um Bearbeitung:

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>

Ihr OTRS Benachrichtigungs-Master',
                'ContentType' => 'text/plain',
                'Subject'     => 'Ticket Eskalations-Warnung! (<OTRS_CUSTOMER_SUBJECT[24]>)'
            },
            'en' => {
                'Body' => 'Hi <OTRS_UserFirstname>,

The ticket [<OTRS_TICKET_TicketNumber>] will escalate!

Escalation at: <OTRS_TICKET_EscalationDestinationDate>
Escalation in: <OTRS_TICKET_EscalationDestinationIn>

<OTRS_CUSTOMER_FROM>

wrote:
<snip>
<OTRS_CUSTOMER_EMAIL[30]>
<snip>

Please have a look at:

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>

Your OTRS Notification Master',
                'ContentType' => 'text/plain',
                'Subject'     => 'Ticket Escalation Warning! (<OTRS_CUSTOMER_SUBJECT[24]>)'
            },
            'nl' => {
                'Body' => 'Beste <OTRS_UserFirstname>,

Het ticket [<OTRS_TICKET_TicketNumber>] gaat escaleren!

Escalatie op:   <OTRS_TICKET_EscalationDestinationDate>
Escalatie over: <OTRS_TICKET_EscalationDestinationIn>

<OTRS_CUSTOMER_FROM> schreef:

<OTRS_CUSTOMER_EMAIL[30]>
(eerste 30 regels zijn weergegeven)

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>
',
                'ContentType' => 'text/plain',
                'Subject'     => 'Ticket gaat escaleren (<OTRS_CUSTOMER_SUBJECT[24]>)'
                }
        },
        'Agent::FollowUp' => {
            'de' => {
                'Body' => 'Hallo <OTRS_UserFirstname> <OTRS_UserLastname>,

Sie haben eine Nachfrage bekommen!

<OTRS_CUSTOMER_FROM> schrieb:

<snip>
<OTRS_CUSTOMER_EMAIL[30]>
<snip>

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>

Ihr OTRS Benachrichtigungs-Master',
                'ContentType' => 'text/plain',
                'Subject'     => 'Nachfrage! (<OTRS_CUSTOMER_SUBJECT[24]>)'
            },
            'en' => {
                'Body' => 'Hi <OTRS_UserFirstname>,

You\'ve got a follow up!

<OTRS_CUSTOMER_FROM> wrote:

<snip>
<OTRS_CUSTOMER_EMAIL[30]>
<snip>

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>

Your OTRS Notification Master',
                'ContentType' => 'text/plain',
                'Subject'     => 'You\'ve got a follow up! (<OTRS_CUSTOMER_SUBJECT[24]>)'
            },
            'nl' => {
                'Body' => 'Beste <OTRS_UserFirstname>,

Er is een reactie ontvangen op onderstaand ticket.

<OTRS_CUSTOMER_FROM> schreef:

<OTRS_CUSTOMER_EMAIL[30]>
(eerste 30 regels zijn weergegeven)

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>
',
                'ContentType' => 'text/plain',
                'Subject'     => 'Reactie ontvangen (<OTRS_CUSTOMER_SUBJECT[24]>)'
                }
        },
        'Agent::LockTimeout' => {
            'de' => {
                'Body' => 'Hallo <OTRS_UserFirstname> <OTRS_UserLastname>,

Aufhebung der Sperre auf Dein gesperrtes Ticket [<OTRS_TICKET_TicketNumber>].

<OTRS_CUSTOMER_FROM> schrieb:

<snip>
<OTRS_CUSTOMER_EMAIL[30]>
<snip>

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>

Ihr OTRS Benachrichtigungs-Master',
                'ContentType' => 'text/plain',
                'Subject'     => 'Lock Timeout! (<OTRS_CUSTOMER_SUBJECT[24]>)'
            },
            'en' => {
                'Body' => 'Hi <OTRS_UserFirstname>,

The lock timeout period on [<OTRS_TICKET_TicketNumber>] has been reached, it is now unlocked.

<OTRS_CUSTOMER_FROM> wrote:

<snip>
<OTRS_CUSTOMER_EMAIL[30]>
<snip>

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>

Your OTRS Notification Master',
                'ContentType' => 'text/plain',
                'Subject'     => 'Lock Timeout! (<OTRS_CUSTOMER_SUBJECT[24]>)'
            },
            'nl' => {
                'Body' => 'Beste <OTRS_UserFirstname>,

De bewerkingstijd van ticket [<OTRS_TICKET_TicketNumber>] is overschreden, het ticket is nu ontgrendeld.

<OTRS_CUSTOMER_FROM> schreef:

<OTRS_CUSTOMER_EMAIL[30]>
(eerste 30 regels zijn weergegeven)

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>
',
                'ContentType' => 'text/plain',
                'Subject'     => 'Ticket ontgrendeld (<OTRS_CUSTOMER_SUBJECT[24]>)'
                }
        },
        'Agent::Move' => {
            'de' => {
                'Body' => 'Hallo <OTRS_UserFirstname> <OTRS_UserLastname>,

<OTRS_CURRENT_UserFirstname> <OTRS_CURRENT_UserLastname> verschob Ticket [<OTRS_TICKET_TicketNumber>] nach "<OTRS_CUSTOMER_QUEUE>".

<snip>
<OTRS_CUSTOMER_EMAIL[30]>
<snip>

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>

Ihr OTRS Benachrichtigungs-Master',
                'ContentType' => 'text/plain',
                'Subject'     => 'Ticket verschoben in "<OTRS_CUSTOMER_QUEUE>" Queue! (<OTRS_CUSTOMER_SUBJECT[24]>)'
            },
            'en' => {
                'Body' => 'Hi <OTRS_UserFirstname>,

<OTRS_CURRENT_UserFirstname> <OTRS_CURRENT_UserLastname> moved a ticket [<OTRS_TICKET_TicketNumber>] into <OTRS_CUSTOMER_QUEUE>.

<snip>
<OTRS_CUSTOMER_EMAIL[30]>
<snip>

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>

Your OTRS Notification Master',
                'ContentType' => 'text/plain',
                'Subject'     => 'Moved ticket in <OTRS_CUSTOMER_QUEUE> queue! (<OTRS_CUSTOMER_SUBJECT[24]>)'
            },
            'nl' => {
                'Body' => 'Beste <OTRS_UserFirstname>,

<OTRS_CURRENT_UserFirstname> <OTRS_CURRENT_UserLastname> heeft [<OTRS_TICKET_TicketNumber>] verplaatst naar <OTRS_CUSTOMER_QUEUE>.

<OTRS_CUSTOMER_EMAIL[30]>
(eerste 30 regels zijn weergegeven)

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>
',
                'ContentType' => 'text/plain',
                'Subject'     => 'Ticket verplaatst naar <OTRS_CUSTOMER_QUEUE> (<OTRS_CUSTOMER_SUBJECT[24]>)'
                }
        },
        'Agent::NewTicket' => {
            'de' => {
                'Body' => 'Hallo <OTRS_UserFirstname> <OTRS_UserLastname>,

es ist ein neues Ticket in <OTRS_TICKET_Queue>!

<OTRS_CUSTOMER_FROM> schrieb:

<snip>
<OTRS_CUSTOMER_EMAIL[30]>
<snip>

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>

Ihr OTRS Benachrichtigungs-Master',
                'ContentType' => 'text/plain',
                'Subject'     => 'Neues Ticket! (<OTRS_CUSTOMER_SUBJECT[24]>)'
            },
            'en' => {
                'Body' => 'Hi <OTRS_UserFirstname>,

There is a new ticket in <OTRS_TICKET_Queue>!

<OTRS_CUSTOMER_FROM> wrote:

<snip>
<OTRS_CUSTOMER_EMAIL[30]>
<snip>

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>

Your OTRS Notification Master',
                'ContentType' => 'text/plain',
                'Subject'     => 'New ticket notification! (<OTRS_CUSTOMER_SUBJECT[24]>)'
            },
            'nl' => {
                'Body' => 'Beste <OTRS_UserFirstname>,

Er is een nieuw ticket aangemaakt in <OTRS_TICKET_Queue>!

<OTRS_CUSTOMER_FROM> schreef:

<OTRS_CUSTOMER_EMAIL[30]>
(eerste 30 regels zijn weergegeven)

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>',
                'ContentType' => 'text/plain',
                'Subject'     => 'Nieuw ticket (<OTRS_CUSTOMER_SUBJECT[24]>)'
                }
        },
        'Agent::OwnerUpdate' => {
            'de' => {
                'Body' => 'Hallo <OTRS_UserFirstname> <OTRS_UserLastname>,

Der Besitz des Tickets [<OTRS_TICKET_TicketNumber>] wurde an Sie von <OTRS_CURRENT_UserFirstname> <OTRS_CURRENT_UserLastname> uebertragen.

Kommentar:

<OTRS_COMMENT>

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>

Ihr OTRS Benachrichtigungs-Master',
                'ContentType' => 'text/plain',
                'Subject'     => 'Ticket Besitz uebertragen an Sie! (<OTRS_CUSTOMER_SUBJECT[24]>)'
            },
            'en' => {
                'Body' => 'Hi <OTRS_UserFirstname>,

Ticket [<OTRS_TICKET_TicketNumber>] is assigned to you by <OTRS_CURRENT_UserFirstname> <OTRS_CURRENT_UserLastname>.

Comment:

<OTRS_COMMENT>

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>

Your OTRS Notification Master',
                'ContentType' => 'text/plain',
                'Subject'     => 'Ticket owner assigned to you! (<OTRS_CUSTOMER_SUBJECT[24]>)'
            },
            'nl' => {
                'Body' => 'Beste <OTRS_UserFirstname>,

Ticket [<OTRS_TICKET_TicketNumber>] is aan jou toegewezen door <OTRS_CURRENT_UserFirstname> <OTRS_CURRENT_UserLastname>.

Opmerking:

<OTRS_COMMENT>

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>
',
                'ContentType' => 'text/plain',
                'Subject'     => 'Ticket toegewezen (<OTRS_CUSTOMER_SUBJECT[24]>)'
                }
        },
        'Agent::PendingReminder' => {
            'de' => {
                'Body' => 'Hallo <OTRS_UserFirstname> <OTRS_UserLastname>,

das Ticket [<OTRS_TICKET_TicketNumber>] hat die Erinnerungszeit erreicht!

<OTRS_CUSTOMER_FROM>

schrieb:
<snip>
<OTRS_CUSTOMER_EMAIL[30]>
<snip>

Bitte um weitere Bearbeitung:

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>

Ihr OTRS Benachrichtigungs-Master',
                'ContentType' => 'text/plain',
                'Subject'     => 'Ticket Erinnerung erreicht! (<OTRS_CUSTOMER_SUBJECT[24]>)'
            },
            'en' => {
                'Body' => 'Hi <OTRS_UserFirstname>,

The ticket [<OTRS_TICKET_TicketNumber>] has reached its reminder time!

<OTRS_CUSTOMER_FROM>

wrote:
<snip>
<OTRS_CUSTOMER_EMAIL[30]>
<snip>

Please have a look at:

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>

Your OTRS Notification Master',
                'ContentType' => 'text/plain',
                'Subject'     => 'Ticket reminder has reached! (<OTRS_CUSTOMER_SUBJECT[24]>)'
            },
            'nl' => {
                'Body' => 'Beste <OTRS_UserFirstname>,

Het herinnermoment voor ticket [<OTRS_TICKET_TicketNumber>] is bereikt.

<OTRS_CUSTOMER_FROM> schreef:

<OTRS_CUSTOMER_EMAIL[30]>
(eerste 30 regels zijn weergegeven)

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>
',
                'ContentType' => 'text/plain',
                'Subject'     => 'Herinnering (<OTRS_CUSTOMER_SUBJECT[24]>)'
                }
        },
        'Agent::ResponsibleUpdate' => {
            'de' => {
                'Body' => 'Hallo <OTRS_RESPONSIBLE_UserFirstname> <OTRS_RESPONSIBLE_UserLastname>,

Die Verantwortung des Tickets [<OTRS_TICKET_TicketNumber>] wurde an Sie von <OTRS_CURRENT_UserFirstname> <OTRS_CURRENT_UserLastname> uebertragen.

Kommentar:

<OTRS_COMMENT>

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>

Ihr OTRS Benachrichtigungs-Master',
                'ContentType' => 'text/plain',
                'Subject'     => 'Ticket Verantwortung uebertragen an Sie! (<OTRS_CUSTOMER_SUBJECT[24]>)'
            },
            'en' => {
                'Body' => 'Hi <OTRS_RESPONSIBLE_UserFirstname>,

Ticket [<OTRS_TICKET_TicketNumber>] is assigned to you by <OTRS_CURRENT_UserFirstname> <OTRS_CURRENT_UserLastname>.

Comment:

<OTRS_COMMENT>

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>

Your OTRS Notification Master',
                'ContentType' => 'text/plain',
                'Subject'     => 'Ticket assigned to you! (<OTRS_CUSTOMER_SUBJECT[24]>)'
            },
            'nl' => {
                'Body' => 'Beste <OTRS_RESPONSIBLE_UserFirstname>,

<OTRS_CURRENT_UserFirstname> <OTRS_CURRENT_UserLastname> heeft je geregistreerd als verantwoordelijke voor ticket [<OTRS_TICKET_TicketNumber>].

Opmerking:

<OTRS_COMMENT>

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>
',
                'ContentType' => 'text/plain',
                'Subject'     => 'Verantwoordelijkheid bijgewerkt (<OTRS_CUSTOMER_SUBJECT[24]>)'
                }
        },
        'Agent::ServiceUpdate' => {
            'de' => {
                'Body' => "Hallo <OTRS_UserFirstname>,

<OTRS_CURRENT_UserFirstname> <OTRS_CURRENT_UserLastname> aktualisierte Ticket [<OTRS_TICKET_TicketNumber>] and änderte den Service zu <OTRS_TICKET_Service>

<snip>
<OTRS_CUSTOMER_EMAIL[30]>
<snip>

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>

Ihr OTRS Benachrichtigungs-Master
",
                'ContentType' => 'text/plain',
                'Subject'     => 'Service aktualisiert zu <OTRS_TICKET_Service>! (<OTRS_CUSTOMER_SUBJECT[24]>)'
            },
            'en' => {
                'Body' => 'Hi <OTRS_UserFirstname>,

<OTRS_CURRENT_UserFirstname> <OTRS_CURRENT_UserLastname> updated a ticket [<OTRS_TICKET_TicketNumber>] and changed the service to <OTRS_TICKET_Service>

<snip>
<OTRS_CUSTOMER_EMAIL[30]>
<snip>

<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>index.pl?Action=AgentTicketZoom;TicketID=<OTRS_TICKET_TicketID>

Your OTRS Notification Master
',
                'ContentType' => 'text/plain',
                'Subject'     => 'Updated service to <OTRS_TICKET_Service>! (<OTRS_CUSTOMER_SUBJECT[24]>)'
                }
            }
    );

    return %NotificationLanguages;

}

1;
