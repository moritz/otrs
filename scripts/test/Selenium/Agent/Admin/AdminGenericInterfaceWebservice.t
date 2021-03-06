# --
# AdminGenericInterfaceWebservice.t - frontend tests for AdminGenericInterfaceWebservice
# Copyright (C) 2001-2015 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

use strict;
use warnings;
use utf8;

use vars (qw($Self));

use Kernel::System::UnitTest::Helper;
use Kernel::System::UnitTest::Selenium;

# get needed objects
my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

my $Selenium = Kernel::System::UnitTest::Selenium->new(
    Verbose => 1,
);

$Selenium->RunTest(
    sub {

        my $Helper = Kernel::System::UnitTest::Helper->new(
            RestoreSystemConfiguration => 0,
        );

        my $TestUserLogin = $Helper->TestUserCreate(
            Groups => ['admin'],
        ) || die "Did not get test user";

        $Selenium->Login(
            Type     => 'Agent',
            User     => $TestUserLogin,
            Password => $TestUserLogin,
        );

        # get test user ID
        my $TestUserID = $Kernel::OM->Get('Kernel::System::User')->UserLookup(
            UserLogin => $TestUserLogin,
        );

        my $ScriptAlias = $ConfigObject->Get('ScriptAlias');

        # go to AdminGenericInterfaceWebservice screen
        $Selenium->get("${ScriptAlias}index.pl?Action=AdminGenericInterfaceWebservice");

        # click 'Add web service' button
        $Selenium->find_element("//button[\@type='submit']")->click();

        # check GenericInterface Web Service Management - Add screen
        for my $ID (
            qw(Name Description RemoteSystem DebugThreshold ValidID ImportButton)
            )
        {
            my $Element = $Selenium->find_element( "#$ID", 'css' );
            $Element->is_enabled();
            $Element->is_displayed();
        }
        $Selenium->find_element( 'Cancel', 'link_text' )->click();

        # set test values
        my %Description = (
            webserviceconfig_1 => 'Connector to send and receive date from Nagios.',
            webserviceconfig_2 => 'Connector to send and receive date from Nagios 2.',
        );

        for my $Webservice (
            qw(webserviceconfig_1 webserviceconfig_2)
            )
        {

            # click 'Add web service' button
            $Selenium->find_element("//button[\@type='submit']")->click();

            # import web service
            $Selenium->find_element( "#ImportButton", 'css' )->click();

            my $File     = $Webservice . '.yml';
            my $Location = $ConfigObject->Get('Home') . "/scripts/test/sample/Webservice/$File";
            $Selenium->find_element( "#ConfigFile",         'css' )->send_keys($Location);
            $Selenium->find_element( "#ImportButtonAction", 'css' )->click();

            # GenericInterface Web Service Management - Change screen
            $Selenium->find_element( $Webservice,                  'link_text' )->click();
            $Selenium->find_element( "#ValidID option[value='2']", 'css' )->click();
            $Selenium->find_element( "#RemoteSystem",              'css' )->send_keys('Test remote system');

            # save edited value
            $Selenium->find_element("//button[\@value='Save and continue'][\@type='submit']")->click();

            # check web service values
            $Self->Is(
                $Selenium->find_element( '#Name', 'css' )->get_value(),
                $Webservice,
                "#Name stored value",
            );

            $Self->Is(
                $Selenium->find_element( '#Description', 'css' )->get_value(),
                $Description{$Webservice},
                '#Description stored value',
            );

            $Self->Is(
                $Selenium->find_element( '#RemoteSystem', 'css' )->get_value(),
                'Test remote system',
                '#RemoteSystem updated value',
            );

            $Self->Is(
                $Selenium->find_element( '#ValidID', 'css' )->get_value(),
                2,
                "#ValidID updated value",
            );

            # delete web service
            $Selenium->find_element( "#DeleteButton",  'css' )->click();
            $Selenium->find_element( "#DialogButton2", 'css' )->click();

            # wait until delete dialog has closed an action performed
            ACTIVESLEEP:
            for my $Second ( 1 .. 20 ) {

                # Test dialog buttons are present
                if ( !$Selenium->execute_script("return \$('#DialogButton2').length") ) {
                    last ACTIVESLEEP;
                }
                print "Waiting to delete web service $Second second(s)...\n\n";
                sleep 1;
            }

            my $Success;
            eval {
                $Success = $Selenium->find_element( $Webservice, 'link_text' )->is_displayed();
            };

            $Self->False(
                $Success,
                "$Webservice is deleted",
            );
        }

    }
);

1;
