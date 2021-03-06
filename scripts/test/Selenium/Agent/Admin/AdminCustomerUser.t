# --
# AdminCustomerUser.t - frontend tests for AdminCustomerUser
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
my $DBObject     = $Kernel::OM->Get('Kernel::System::DB');

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

        my $ScriptAlias = $ConfigObject->Get('ScriptAlias');

        $Selenium->get("${ScriptAlias}index.pl?Action=AdminCustomerUser");

        # check AdminCustomerCompany screen
        $Selenium->find_element( "table",             'css' );
        $Selenium->find_element( "table thead tr th", 'css' );
        $Selenium->find_element( "table tbody tr td", 'css' );
        $Selenium->find_element( "#Source",           'css' );
        $Selenium->find_element( "#Search",           'css' );

        # click 'Add customer user' link
        $Selenium->find_element( "button.CallForAction", 'css' )->click();

        # check add customer user screen
        for my $ID (
            qw(UserFirstname UserLastname UserLogin UserEmail UserCustomerID ValidID)
            )
        {
            my $Element = $Selenium->find_element( "#$ID", 'css' );
            $Element->is_enabled();
            $Element->is_displayed();
        }

        # check client side validation
        $Selenium->find_element( "#UserFirstname", 'css' )->clear();
        $Selenium->find_element( "#UserFirstname", 'css' )->submit();
        $Self->Is(
            $Selenium->execute_script(
                "return \$('#UserFirstname').hasClass('Error')"
            ),
            '1',
            'Client side validation correctly detected missing input value',
        );

        # create a real test customer user
        my $RandomID = $Helper->GetRandomID();

        $Selenium->find_element( "#UserFirstname",  'css' )->send_keys($RandomID);
        $Selenium->find_element( "#UserLastname",   'css' )->send_keys($RandomID);
        $Selenium->find_element( "#UserLogin",      'css' )->send_keys($RandomID);
        $Selenium->find_element( "#UserEmail",      'css' )->send_keys( $RandomID . "\@localhost.com" );
        $Selenium->find_element( "#UserCustomerID", 'css' )->send_keys($RandomID);
        $Selenium->find_element( "#UserFirstname",  'css' )->submit();

        # check overview page
        $Self->True(
            index( $Selenium->get_page_source(), $RandomID ) > -1,
            "$RandomID found on page",
        );

        # create another test customer user for filter search test
        my $RandomID2 = $Helper->GetRandomID();

        $Selenium->find_element( "button.CallForAction", 'css' )->click();
        $Selenium->find_element( "#UserFirstname",       'css' )->send_keys($RandomID2);
        $Selenium->find_element( "#UserLastname",        'css' )->send_keys($RandomID2);
        $Selenium->find_element( "#UserLogin",           'css' )->send_keys($RandomID2);
        $Selenium->find_element( "#UserEmail",           'css' )->send_keys( $RandomID2 . "\@localhost.com" );
        $Selenium->find_element( "#UserCustomerID",      'css' )->send_keys($RandomID2);
        $Selenium->find_element( "#UserFirstname",       'css' )->submit();

        # check for another customer user
        $Self->True(
            index( $Selenium->get_page_source(), $RandomID2 ) > -1,
            "$RandomID2 found on page",
        );

        # test search filter
        $Selenium->find_element( "#Search", 'css' )->clear();
        $Selenium->find_element( "#Search", 'css' )->send_keys($RandomID);
        $Selenium->find_element( "#Search", 'css' )->submit();

        $Self->True(
            index( $Selenium->get_page_source(), $RandomID ) > -1,
            "$RandomID found on page",
        );
        $Self->False(
            index( $Selenium->get_page_source(), $RandomID2 ) > -1,
            "$RandomID2 not found on page",
        );

        # check and edit new customer user
        $Selenium->find_element( $RandomID, 'link_text' )->click();

        $Self->Is(
            $Selenium->find_element( '#UserFirstname', 'css' )->get_value(),
            $RandomID,
            "#UserFirstname updated value",
        );
        $Self->Is(
            $Selenium->find_element( '#UserLastname', 'css' )->get_value(),
            $RandomID,
            "#UserLastname updated value",
        );
        $Self->Is(
            $Selenium->find_element( '#UserLogin', 'css' )->get_value(),
            $RandomID,
            "#UserLogin updated value",
        );
        $Self->Is(
            $Selenium->find_element( '#UserEmail', 'css' )->get_value(),
            "$RandomID\@localhost.com",
            "#UserLastname updated value",
        );
        $Self->Is(
            $Selenium->find_element( '#UserCustomerID', 'css' )->get_value(),
            $RandomID,
            "#UserCustomerID updated value",
        );

        # set test customer user to invalid
        $Selenium->find_element( "#ValidID option[value='2']", 'css' )->click();
        $Selenium->find_element( "#UserFirstname",             'css' )->submit();

        # delete created test customer user
        if ($RandomID) {
            my $Success = $DBObject->Do(
                SQL  => "DELETE FROM customer_user WHERE customer_id = ?",
                Bind => [ \$RandomID ],
            );
            $Self->True(
                $Success,
                "Deleted CustomerUser - $RandomID",
            );
        }

        if ($RandomID2) {
            my $Success2 = $DBObject->Do(
                SQL  => "DELETE FROM customer_user WHERE customer_id = ?",
                Bind => [ \$RandomID2 ],
            );
            $Self->True(
                $Success2,
                "Deleted CustomerUser - $RandomID2",
            );
        }

        # Make sure the cache is correct.
        $Kernel::OM->Get('Kernel::System::Cache')->CleanUp(
            Type => 'CustomerUser',
        );

    }

);

1;
