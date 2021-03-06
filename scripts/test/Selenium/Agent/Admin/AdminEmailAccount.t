# --
# AdminEmailAccount.t - frontend tests for AdminEmailAccount
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
my $ConfigObject      = $Kernel::OM->Get('Kernel::Config');
my $MailAccountObject = $Kernel::OM->Get('Kernel::System::MailAccount');
$Kernel::OM->Get('Kernel::System::DB');

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

        $Selenium->get("${ScriptAlias}index.pl?Action=AdminMailAccount");

        # check AdminMailAccount screen
        $Selenium->find_element( "table",             'css' );
        $Selenium->find_element( "table thead tr th", 'css' );
        $Selenium->find_element( "table tbody tr td", 'css' );

        # check "Add mail account" link
        $Selenium->find_element("//a[contains(\@href, \'Subaction=AddNew' )]")->click();

        for my $ID (
            qw(TypeAdd LoginAdd PasswordAdd HostAdd IMAPFolder Trusted DispatchingBy ValidID Comment)
            )
        {
            my $Element = $Selenium->find_element( "#$ID", 'css' );
            $Element->is_enabled();
            $Element->is_displayed();
        }

        # add real test mail account
        my $RandomID = $Helper->GetRandomID();

        $Selenium->find_element( "#TypeAdd option[value='IMAP']",        'css' )->click();
        $Selenium->find_element( "#LoginAdd",                            'css' )->send_keys($RandomID);
        $Selenium->find_element( "#PasswordAdd",                         'css' )->send_keys("SomePassword");
        $Selenium->find_element( "#HostAdd",                             'css' )->send_keys("pop3.example.com");
        $Selenium->find_element( "#Trusted option[value='0']",           'css' )->click();
        $Selenium->find_element( "#DispatchingBy option[value='Queue']", 'css' )->click();
        $Selenium->find_element( "#Comment",  'css' )->send_keys("Selenium test AdminMailAccount");
        $Selenium->find_element( "#LoginAdd", 'css' )->submit();

        # check if test mail account is present
        my $TestMailHost = "pop3.example.com / $RandomID";
        $Self->True(
            index( $Selenium->get_page_source(), $TestMailHost ) > -1,
            "$TestMailHost found on page",
        );

        # edit test mail account and set it to invalid
        $Selenium->find_element( $TestMailHost, 'link_text' )->click();

        $Selenium->find_element( "#HostEdit",                  'css' )->clear();
        $Selenium->find_element( "#HostEdit",                  'css' )->send_keys("pop3edit.example.com");
        $Selenium->find_element( "#ValidID option[value='2']", 'css' )->click();
        $Selenium->find_element( "#LoginEdit",                 'css' )->submit();

        # check for edited mail account
        my $TestMailHostEdit = "pop3edit.example.com / $RandomID";
        $Self->True(
            index( $Selenium->get_page_source(), $TestMailHostEdit ) > -1,
            "$TestMailHostEdit found on page",
        );

        # test mail account delete button
        my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
        my $Success  = $DBObject->Prepare(
            SQL => "SELECT id FROM mail_account WHERE login='$RandomID'",
        );

        if ($Success) {
            my $MailAccountID;
            while ( my @Row = $DBObject->FetchrowArray() ) {
                $MailAccountID = $Row[0];
            }
            $Selenium->find_element("//a[contains(\@href, \'Subaction=Delete;ID=$MailAccountID' )]")->click();
        }

    }

);

1;
