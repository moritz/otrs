# --
# AdminCustomerCompany.t - frontend tests for AdminCustomerCompany
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

        $Selenium->get("${ScriptAlias}index.pl?Action=AdminCustomerCompany");

        # check AdminCustomerCompany screen
        $Selenium->find_element( "table",             'css' );
        $Selenium->find_element( "table thead tr th", 'css' );
        $Selenium->find_element( "table tbody tr td", 'css' );
        $Selenium->find_element( "#Source",           'css' );
        $Selenium->find_element( "#Search",           'css' );

        # click 'Add customer' link
        $Selenium->find_element( "button.CallForAction", 'css' )->click();

        # check add customer screen
        for my $ID (
            qw(CustomerID CustomerCompanyName CustomerCompanyComment ValidID)
            )
        {
            my $Element = $Selenium->find_element( "#$ID", 'css' );
            $Element->is_enabled();
            $Element->is_displayed();
        }

        # check client side validation
        $Selenium->find_element( "#CustomerID", 'css' )->clear();
        $Selenium->find_element( "#CustomerID", 'css' )->submit();
        $Self->Is(
            $Selenium->execute_script(
                "return \$('#CustomerID').hasClass('Error')"
            ),
            '1',
            'Client side validation correctly detected missing input value',
        );

        # create a real test customer company
        my $RandomID = $Helper->GetRandomID();

        $Selenium->find_element( "#CustomerID",                'css' )->send_keys($RandomID);
        $Selenium->find_element( "#CustomerCompanyName",       'css' )->send_keys($RandomID);
        $Selenium->find_element( "#ValidID option[value='1']", 'css' )->click();
        $Selenium->find_element( "#CustomerCompanyComment",    'css' )->send_keys('Selenium test customer company');
        $Selenium->find_element( "#CustomerID",                'css' )->submit();

        # check overview page
        $Self->True(
            index( $Selenium->get_page_source(), $RandomID ) > -1,
            "$RandomID found on page",
        );

        # create another test customer company for filter search test
        my $RandomID2 = $Helper->GetRandomID();

        $Selenium->find_element("//button[\@type='submit']")->click();
        $Selenium->find_element( "button.CallForAction", 'css' )->click();
        $Selenium->find_element( "#CustomerID",          'css' )->send_keys($RandomID2);
        $Selenium->find_element( "#CustomerCompanyName", 'css' )->send_keys($RandomID2);
        $Selenium->find_element( "#CustomerID",          'css' )->submit();

        # check for another customer company
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

        # check and edit new customer company
        $Selenium->find_element( $RandomID, 'link_text' )->click();

        $Self->Is(
            $Selenium->find_element( '#CustomerID', 'css' )->get_value(),
            $RandomID,
            "#CustomerID updated value",
        );
        $Self->Is(
            $Selenium->find_element( '#CustomerCompanyName', 'css' )->get_value(),
            $RandomID,
            "#CustomerCompanyName updated value",
        );
        $Self->Is(
            $Selenium->find_element( '#ValidID', 'css' )->get_value(),
            1,
            "#ValidID updated value",
        );
        $Self->Is(
            $Selenium->find_element( '#CustomerCompanyComment', 'css' )->get_value(),
            'Selenium test customer company',
            "#CustomerCompanyComment updated value",
        );

        # set test customer company to invalid and clear comment
        $Selenium->find_element( "#ValidID option[value='2']", 'css' )->click();
        $Selenium->find_element( "#CustomerCompanyComment",    'css' )->clear();
        $Selenium->find_element( "#CustomerID",                'css' )->submit();

        # delete created test customer companies
        if ($RandomID) {
            my $Success = $DBObject->Do(
                SQL  => "DELETE FROM customer_company WHERE customer_id = ?",
                Bind => [ \$RandomID ],
            );
            $Self->True(
                $Success,
                "Deleted CustomerCompany - $RandomID",
            );
        }

        if ($RandomID2) {
            my $Success = $DBObject->Do(
                SQL  => "DELETE FROM customer_company WHERE customer_id = ?",
                Bind => [ \$RandomID2 ],
            );
            $Self->True(
                $Success,
                "Deleted CustomerCompany - $RandomID2",
            );
        }

        # Make sure the cache is correct.
        $Kernel::OM->Get('Kernel::System::Cache')->CleanUp(
            Type => 'CustomerCompany',
        );

    }
);

1;
