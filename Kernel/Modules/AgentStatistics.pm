# --
# Copyright (C) 2001-2015 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::AgentStatistics;

use strict;
use warnings;

use List::Util qw( first );

use Kernel::System::VariableCheck qw(:all);

#use Kernel::Language qw(Translatable);

our $ObjectManagerDisabled = 1;

# TODO remove after notification merge in master
sub Translatable {
    return shift;
}

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    for my $NeededData (qw( UserID Subaction AccessRo SessionID ))
    {
        if ( !$Param{$NeededData} ) {
            $Kernel::OM->Get('Kernel::Output::HTML::Layout')->FatalError( Message => "Got no $NeededData!" );
        }
        $Self->{$NeededData} = $Param{$NeededData};
    }

    # AccessRw controls the adding/editing of statistics.
    for my $Param (qw( AccessRw RequestedURL)) {
        if ( $Param{$Param} ) {
            $Self->{$Param} = $Param{$Param};
        }
    }

    # Create stats object (requires UserID).
    $Kernel::OM->ObjectParamAdd(
        'Kernel::System::Stats' => {
            UserID => $Param{UserID},
        },
    );
    $Self->{StatsObject} = $Kernel::OM->Get('Kernel::System::Stats');

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    if ( $Self->{Subaction} eq 'Overview' ) {
        return $Self->OverviewScreen();
    }
    elsif ( $Self->{Subaction} eq 'Add' ) {
        return $Self->AddScreen();
    }
    elsif ( $Self->{Subaction} eq 'Import' ) {
        return $Self->ImportScreen();
    }
    elsif ( $Self->{Subaction} eq 'Export' ) {
        return $Self->ExportAction();
    }
    elsif ( $Self->{Subaction} eq 'Delete' ) {
        return $Self->DeleteAction();
    }
    elsif ( $Self->{Subaction} eq 'Edit' ) {
        return $Self->EditScreen();
    }
    elsif ( $Self->{Subaction} eq 'View' ) {
        return $Self->ViewScreen();
    }
    elsif ( $Self->{Subaction} eq 'Run' ) {
        return $Self->RunAction();
    }
    elsif ( $Self->{Subaction} eq 'GeneralSpecificationsWidgetAJAX' ) {
        return $Self->GeneralSpecificationsWidgetAJAX();
    }

    # No (known) subaction?
    return $Kernel::OM->Get('Kernel::Output::HTML::Layout')->ErrorScreen( Message => 'Invalid Subaction.' );
}

sub OverviewScreen {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # permission check
    $Self->{AccessRo} || return $LayoutObject->NoPermission( WithHeader => 'yes' );

    # Get Params
    $Param{SearchPageShown} = $ConfigObject->Get('Stats::SearchPageShown') || 10;
    $Param{SearchLimit}     = $ConfigObject->Get('Stats::SearchLimit')     || 100;
    $Param{OrderBy}   = $ParamObject->GetParam( Param => 'OrderBy' )   || 'ID';
    $Param{Direction} = $ParamObject->GetParam( Param => 'Direction' ) || 'ASC';
    $Param{StartHit} = int( $ParamObject->GetParam( Param => 'StartHit' ) || 1 );

    # store last screen
    $Kernel::OM->Get('Kernel::System::AuthSession')->UpdateSessionID(
        SessionID => $Self->{SessionID},
        Key       => 'LastStatsOverview',
        Value     => $Self->{RequestedURL},
        StoreData => 1,
    );

    # get all Stats from the db
    my $Result = $Self->{StatsObject}->GetStatsList(
        AccessRw  => $Self->{AccessRw},
        OrderBy   => $Param{OrderBy},
        Direction => $Param{Direction},
    );

    my %Order2CSSSort = (
        ASC  => 'SortAscending',
        DESC => 'SortDescending',
    );

    my %InverseSorting = (
        ASC  => 'DESC',
        DESC => 'ASC',
    );

    $Param{ 'CSSSort' . $Param{OrderBy} } = $Order2CSSSort{ $Param{Direction} };
    for my $Type (qw(ID Title Object)) {
        $Param{"LinkSort$Type"} = ( $Param{OrderBy} eq $Type ) ? $InverseSorting{ $Param{Direction} } : 'ASC';
    }

    # build the info
    my %Pagination = $LayoutObject->PageNavBar(
        Limit     => $Param{SearchLimit},
        StartHit  => $Param{StartHit},
        PageShown => $Param{SearchPageShown},
        AllHits   => $#{$Result} + 1,
        Action    => 'Action=AgentStatistics;Subaction=Overview',
        Link      => ";Direction=$Param{Direction};OrderBy=$Param{OrderBy};",
        IDPrefix  => 'AgentStatisticsOverview'
    );

    # list result
    my $Index = -1;
    for ( my $Z = 0; ( $Z < $Param{SearchPageShown} && $Index < $#{$Result} ); $Z++ ) {
        $Index = $Param{StartHit} + $Z - 1;
        my $StatID = $Result->[$Index];
        my $Stat   = $Self->{StatsObject}->StatsGet(
            StatID             => $StatID,
            NoObjectAttributes => 1,
        );

        # get the object name
        if ( $Stat->{StatType} eq 'static' ) {
            $Stat->{ObjectName} = $Stat->{File};
        }

        # if no object name is defined use an empty string
        $Stat->{ObjectName} ||= '';

        $LayoutObject->Block(
            Name => 'Result',
            Data => {
                %$Stat,
                AccessRw => $Self->{AccessRw},
            },
        );
    }

    # build output
    my $Output = $LayoutObject->Header( Title => 'Overview' );
    $Output .= $LayoutObject->NavigationBar();
    $Output .= $LayoutObject->Output(
        Data => {
            %Pagination,
            %Param,
            AccessRw => $Self->{AccessRw},
        },
        TemplateFile => 'AgentStatisticsOverview',
    );
    $Output .= $LayoutObject->Footer();
    return $Output;
}

sub ImportScreen {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');

    if ( !$Self->{AccessRw} ) {
        return $LayoutObject->NoPermission( WithHeader => 'yes' )
    }

    my %Error;
    my $Status = $ParamObject->GetParam( Param => 'Status' );

    if ( $Status && $Status eq 'Action' ) {

        # challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        my $UploadFile = $ParamObject->GetParam( Param => 'File' );
        if ($UploadFile) {
            my %UploadStuff = $ParamObject->GetUploadAll(
                Param    => 'File',
                Encoding => 'Raw'
            );
            if ( $UploadStuff{Content} =~ m{<otrs_stats>}x ) {
                my $StatID = $Self->{StatsObject}->Import(
                    Content => $UploadStuff{Content},
                );

                if ($StatID) {
                    $Error{FileServerError}        = 'ServerError';
                    $Error{FileServerErrorMessage} = Translatable("Statistic could not be imported.");
                }

                # redirect to configure
                return $LayoutObject->Redirect(
                    OP => "Action=AgentStatistics;Subaction=Edit;StatID=$StatID"
                );
            }
            else {
                $Error{FileServerError}        = 'ServerError';
                $Error{FileServerErrorMessage} = Translatable("Please upload a valid statistic file.");
            }
        }
        else {
            $Error{FileServerError}        = 'ServerError';
            $Error{FileServerErrorMessage} = Translatable("This field is required.");
        }
    }

    my $Output = $LayoutObject->Header( Title => 'Import' );
    $Output .= $LayoutObject->NavigationBar();
    $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentStatisticsImport',
        Data         => {
            %Error,
        },
    );
    $Output .= $LayoutObject->Footer();
    return $Output;
}

sub ExportAction {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    if ( !$Self->{AccessRw} ) {
        return $LayoutObject->NoPermission( WithHeader => 'yes' );
    }

    $LayoutObject->ChallengeTokenCheck();

    my $StatID = $Kernel::OM->Get('Kernel::System::Web::Request')->GetParam( Param => 'StatID' );
    if ( !$StatID ) {
        return $LayoutObject->ErrorScreen( Message => 'Export: Need StatID!' );
    }

    my $ExportFile = $Self->{StatsObject}->Export( StatID => $StatID );

    return $LayoutObject->Attachment(
        Filename    => $ExportFile->{Filename},
        Content     => $ExportFile->{Content},
        ContentType => 'text/xml',
    );
}

sub DeleteAction {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');

    if ( !$Self->{AccessRw} ) {
        return $LayoutObject->NoPermission( WithHeader => 'yes' );
    }

    my $StatID = $ParamObject->GetParam( Param => 'StatID' );
    if ( !$StatID ) {
        return $LayoutObject->ErrorScreen( Message => 'Delete: Get no StatID!' );
    }

    # challenge token check for write action
    $LayoutObject->ChallengeTokenCheck();
    $Self->{StatsObject}->StatsDelete( StatID => $StatID );
    return $LayoutObject->Redirect( OP => 'Action=AgentStatistics;Subaction=Overview' );
}

sub EditScreen {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # permission check
    return $LayoutObject->NoPermission( WithHeader => 'yes' ) if !$Self->{AccessRw};

    # get param
    if ( !( $Param{StatID} = $ParamObject->GetParam( Param => 'StatID' ) ) ) {
        return $LayoutObject->ErrorScreen(
            Message => 'EditSpecification: Need StatID!',
        );
    }

    my $Stat = $Self->{StatsObject}->StatsGet( StatID => $Param{StatID} );

    my %Frontend;
    $Frontend{GeneralSpecificationsWidget} = $Self->_GeneralSpecificationsWidget(
        StatID => $Stat->{StatID},
    );

    if ( $Stat->{StatType} eq 'dynamic' ) {
        $Kernel::OM->ObjectParamAdd(
            'Kernel::Output::HTML::Statistics::View' => {
                StatsObject => $Self->{StatsObject},
            },
        );
        $Frontend{PreviewContainer} = $Kernel::OM->Get('Kernel::Output::HTML::Statistics::View')->PreviewContainer(
            Stat => $Stat,
        );
    }

    my $Output = $LayoutObject->Header( Title => 'Edit' );
    $Output .= $LayoutObject->NavigationBar();
    $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentStatisticsEdit',
        Data         => {
            %Frontend,
            %{$Stat},
        },
    );
    $Output .= $LayoutObject->Footer();
    return $Output;
}

sub ViewScreen {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # permission check
    $Self->{AccessRo} || return $LayoutObject->NoPermission( WithHeader => 'yes' );

    # get StatID
    my $StatID = $ParamObject->GetParam( Param => 'StatID' );
    if ( !$StatID ) {
        return $LayoutObject->ErrorScreen( Message => 'Need StatID!' );
    }

    # get message if one available
    #my $Message = $ParamObject->GetParam( Param => 'Message' );

    # Get all statistics that the current user may see (does permission check).
    my $StatsList = $Self->{StatsObject}->StatsListGet();
    if ( !IsHashRefWithData( $StatsList->{$StatID} ) ) {
        return $LayoutObject->ErrorScreen(
            Message => 'Could not load stat.',
        );
    }

    my $Stat = $Self->{StatsObject}->StatsGet(
        StatID => $StatID,
    );

    # get param
    if ( !IsHashRefWithData($Stat) ) {
        return $LayoutObject->ErrorScreen(
            Message => 'Could not load stat.',
        );
    }

    my %Frontend;

    $Kernel::OM->ObjectParamAdd(
        'Kernel::Output::HTML::Statistics::View' => {
            StatsObject => $Self->{StatsObject},
        },
    );
    $Frontend{StatsViewParameterWidget}
        = $Kernel::OM->Get('Kernel::Output::HTML::Statistics::View')->StatsViewParameterWidget(
        Stat => $Stat,
        );

    my $Output = $LayoutObject->Header( Title => 'View' );
    $Output .= $LayoutObject->NavigationBar();
    $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentStatisticsView',
        Data         => {
            AccessRw => $Self->{AccessRw},
            %Frontend,
            %{$Stat},
        },
    );
    $Output .= $LayoutObject->Footer();
    return $Output;
}

sub AddScreen {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    if ( !$Self->{AccessRw} ) {
        return $LayoutObject->NoPermission( WithHeader => 'yes' );
    }

    my %Frontend;
    $Frontend{GeneralSpecificationsWidget} = $Self->_GeneralSpecificationsWidget();

    # build output
    my $Output = $LayoutObject->Header( Title => 'Add New Statistic' );
    $Output .= $LayoutObject->NavigationBar();
    $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentStatisticsAdd',
        Data         => {
            %Frontend,
        },
    );
    $Output .= $LayoutObject->Footer();
    return $Output;
}

sub RunAction {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # permission check
    $Self->{AccessRo} || return $LayoutObject->NoPermission( WithHeader => 'yes' );

    # get params
    for (qw(Format GraphSize StatID ExchangeAxis Name Cached)) {
        $Param{$_} = $ParamObject->GetParam( Param => $_ );
    }
    my @RequiredParams = (qw(Format StatID));
    if ( $Param{Cached} ) {
        push @RequiredParams, 'Name';
    }
    for my $Required (@RequiredParams) {
        if ( !$Param{$Required} ) {
            return $LayoutObject->ErrorScreen( Message => "Run: Get no $Required!" );
        }
    }

    if ( $Param{Format} =~ m{^GD::Graph\.*}x ) {

        # check installed packages
        for my $Module ( 'GD', 'GD::Graph' ) {
            if ( !$$Kernel::OM->Get('Kernel::System::Main')->Require($Module) ) {
                return $LayoutObject->ErrorScreen(
                    Message => "Run: Please install $Module module!"
                );
            }
        }
        if ( !$Param{GraphSize} ) {
            return $LayoutObject->ErrorScreen( Message => 'Run: Need GraphSize!' );
        }
    }

    my $Stat = $Self->{StatsObject}->StatsGet( StatID => $Param{StatID} );

    # permission check
    if ( !$Self->{AccessRw} ) {
        my $UserPermission = 0;

        return $LayoutObject->NoPermission( WithHeader => 'yes' ) if !$Stat->{Valid};

        # get user groups
        my %GroupList = $Kernel::OM->Get('Kernel::System::Group')->PermissionUserGet(
            UserID => $Self->{UserID},
            Type   => 'ro',
        );

        GROUPID:
        for my $GroupID ( @{ $Stat->{Permission} } ) {

            next GROUPID if !$GroupID;
            next GROUPID if !$GroupList{$GroupID};

            $UserPermission = 1;

            last GROUPID;
        }

        return $LayoutObject->NoPermission( WithHeader => 'yes' ) if !$UserPermission;
    }

    # get params
    my %GetParam;

    # not sure, if this is the right way
    if ( $Stat->{StatType} eq 'static' ) {
        my $Params = $Self->{StatsObject}->GetParams( StatID => $Param{StatID} );
        PARAMITEM:
        for my $ParamItem ( @{$Params} ) {

            # param is array
            if ( $ParamItem->{Multiple} ) {
                my @Array = $ParamObject->GetArray( Param => $ParamItem->{Name} );
                $GetParam{ $ParamItem->{Name} } = \@Array;
                next PARAMITEM;
            }

            # param is string
            $GetParam{ $ParamItem->{Name} } = $ParamObject->GetParam( Param => $ParamItem->{Name} );
        }
    }
    else {
        my $TimePeriod = 0;

        for my $Use (qw(UseAsRestriction UseAsXvalue UseAsValueSeries)) {
            $Stat->{$Use} ||= [];

            my @Array   = @{ $Stat->{$Use} };
            my $Counter = 0;
            ELEMENT:
            for my $Element (@Array) {
                next ELEMENT if !$Element->{Selected};

                if ( !$Element->{Fixed} ) {
                    if ( $ParamObject->GetArray( Param => $Use . $Element->{Element} ) )
                    {
                        my @SelectedValues = $ParamObject->GetArray(
                            Param => $Use . $Element->{Element}
                        );

                        $Element->{SelectedValues} = \@SelectedValues;
                    }
                    if ( $Element->{Block} eq 'Time' ) {

                        # get time object
                        my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

                        if (
                            $ParamObject->GetParam(
                                Param => $Use . $Element->{Element} . 'StartYear'
                            )
                            )
                        {
                            my %Time;
                            for my $Limit (qw(Start Stop)) {
                                for my $Unit (qw(Year Month Day Hour Minute Second)) {
                                    if (
                                        defined(
                                            $ParamObject->GetParam(
                                                Param => $Use
                                                    . $Element->{Element}
                                                    . "$Limit$Unit"
                                                )
                                        )
                                        )
                                    {
                                        $Time{ $Limit . $Unit } = $ParamObject->GetParam(
                                            Param => $Use . $Element->{Element} . "$Limit$Unit",
                                        );
                                    }
                                }
                                if ( !defined( $Time{ $Limit . 'Hour' } ) ) {
                                    if ( $Limit eq 'Start' ) {
                                        $Time{StartHour}   = 0;
                                        $Time{StartMinute} = 0;
                                        $Time{StartSecond} = 0;
                                    }
                                    elsif ( $Limit eq 'Stop' ) {
                                        $Time{StopHour}   = 23;
                                        $Time{StopMinute} = 59;
                                        $Time{StopSecond} = 59;
                                    }
                                }
                                elsif ( !defined( $Time{ $Limit . 'Second' } ) ) {
                                    if ( $Limit eq 'Start' ) {
                                        $Time{StartSecond} = 0;
                                    }
                                    elsif ( $Limit eq 'Stop' ) {
                                        $Time{StopSecond} = 59;
                                    }
                                }
                                $Time{"Time$Limit"} = sprintf(
                                    "%04d-%02d-%02d %02d:%02d:%02d",
                                    $Time{ $Limit . 'Year' },
                                    $Time{ $Limit . 'Month' },
                                    $Time{ $Limit . 'Day' },
                                    $Time{ $Limit . 'Hour' },
                                    $Time{ $Limit . 'Minute' },
                                    $Time{ $Limit . 'Second' },
                                );
                            }

                            # integrate this functionality in the completenesscheck
                            if (
                                $TimeObject->TimeStamp2SystemTime(
                                    String => $Time{TimeStart}
                                )
                                < $TimeObject->TimeStamp2SystemTime(
                                    String => $Element->{TimeStart}
                                )
                                )
                            {

                                # redirect to edit
                                return $LayoutObject->Redirect(
                                    OP =>
                                        "Action=AgentStatistics;Subaction=View;StatID=$Param{StatID};Message=1",
                                );
                            }

                            # integrate this functionality in the completenesscheck
                            if (
                                $TimeObject->TimeStamp2SystemTime(
                                    String => $Time{TimeStop}
                                )
                                > $TimeObject->TimeStamp2SystemTime(
                                    String => $Element->{TimeStop}
                                )
                                )
                            {
                                return $LayoutObject->Redirect(
                                    OP =>
                                        "Action=AgentStatistics;Subaction=View;StatID=$Param{StatID};Message=2",
                                );
                            }
                            $Element->{TimeStart} = $Time{TimeStart};
                            $Element->{TimeStop}  = $Time{TimeStop};
                            $TimePeriod           = (
                                $TimeObject->TimeStamp2SystemTime(
                                    String => $Element->{TimeStop}
                                    )
                                )
                                - (
                                $TimeObject->TimeStamp2SystemTime(
                                    String => $Element->{TimeStart}
                                    )
                                );
                        }
                        else {
                            my %Time;
                            my ( $s, $m, $h, $D, $M, $Y ) = $TimeObject->SystemTime2Date(
                                SystemTime => $TimeObject->SystemTime(),
                            );
                            $Time{TimeRelativeUnit} = $ParamObject->GetParam(
                                Param => $Use . $Element->{Element} . 'TimeRelativeUnit'
                            );
                            if (
                                $ParamObject->GetParam(
                                    Param => $Use . $Element->{Element} . 'TimeRelativeCount'
                                )
                                )
                            {
                                $Time{TimeRelativeCount} = $ParamObject->GetParam(
                                    Param => $Use . $Element->{Element} . 'TimeRelativeCount'
                                );
                            }

                            my $TimePeriodAdmin = $Element->{TimeRelativeCount}
                                * $Self->_TimeInSeconds(
                                TimeUnit => $Element->{TimeRelativeUnit}
                                );
                            my $TimePeriodAgent = $Time{TimeRelativeCount}
                                * $Self->_TimeInSeconds( TimeUnit => $Time{TimeRelativeUnit} );

                            # integrate this functionality in the completenesscheck
                            if ( $TimePeriodAgent > $TimePeriodAdmin ) {
                                return $LayoutObject->Redirect(
                                    OP =>
                                        "Action=AgentStatistics;Subaction=View;StatID=$Param{StatID};Message=3",
                                );
                            }

                            $TimePeriod                   = $TimePeriodAgent;
                            $Element->{TimeRelativeCount} = $Time{TimeRelativeCount};
                            $Element->{TimeRelativeUnit}  = $Time{TimeRelativeUnit};
                        }
                        if (
                            $ParamObject->GetParam(
                                Param => $Use . $Element->{Element} . 'TimeScaleCount'
                            )
                            )
                        {
                            $Element->{TimeScaleCount} = $ParamObject->GetParam(
                                Param => $Use . $Element->{Element} . 'TimeScaleCount'
                            );
                        }
                        else {
                            $Element->{TimeScaleCount} = 1;
                        }
                    }
                }

                $GetParam{$Use}[$Counter] = $Element;
                $Counter++;

            }
            if ( ref $GetParam{$Use} ne 'ARRAY' ) {
                $GetParam{$Use} = [];
            }
        }

        # check if the timeperiod is too big or the time scale too small
        if (
            $GetParam{UseAsXvalue}[0]{Block} eq 'Time'
            && (
                !$GetParam{UseAsValueSeries}[0]
                || (
                    $GetParam{UseAsValueSeries}[0]
                    && $GetParam{UseAsValueSeries}[0]{Block} ne 'Time'
                )
            )
            )
        {

            my $ScalePeriod = $Self->_TimeInSeconds(
                TimeUnit => $GetParam{UseAsXvalue}[0]{SelectedValues}[0]
            );

            # integrate this functionality in the completenesscheck
            if (
                $TimePeriod / ( $ScalePeriod * $GetParam{UseAsXvalue}[0]{TimeScaleCount} )
                > ( $ConfigObject->Get('Stats::MaxXaxisAttributes') || 1000 )
                )
            {
                return $LayoutObject->Redirect(
                    OP => "Action=AgentStatistics;Subaction=View;StatID=$Param{StatID};Message=4",
                );
            }
        }
    }

    # run stat...
    my @StatArray;

    # called from within the dashboard. will use the same mechanism and configuration like in
    # the dashboard stats - the (cached) result will be the same as seen in the dashboard
    if ( $Param{Cached} ) {

        # get settings for specified stats by using the dashboard configuration for the agent
        my %Preferences = $$Kernel::OM->Get('Kernel::System::User')->GetPreferences(
            UserID => $Self->{UserID},
        );
        my $PrefKeyStatsConfiguration = 'UserDashboardStatsStatsConfiguration' . $Param{Name};
        my $StatsSettings             = {};
        if ( $Preferences{$PrefKeyStatsConfiguration} ) {
            $StatsSettings = $Kernel::OM->Get('Kernel::System::JSON')->Decode(
                Data => $Preferences{$PrefKeyStatsConfiguration},
            );
        }
        @StatArray = @{
            $Self->{StatsObject}->StatsResultCacheGet(
                StatID       => $Param{StatID},
                UserGetParam => $StatsSettings,
            );
            }
    }

    # called normally within the stats area - generate stats now and use provided configuraton
    else {
        @StatArray = @{
            $Self->{StatsObject}->StatsRun(
                StatID   => $Param{StatID},
                GetParam => \%GetParam,
            );
        };
    }

    # exchange axis if selected
    if ( $Param{ExchangeAxis} ) {
        my @NewStatArray;
        my $Title = $StatArray[0][0];

        shift(@StatArray);
        for my $Key1 ( 0 .. $#StatArray ) {
            for my $Key2 ( 0 .. $#{ $StatArray[0] } ) {
                $NewStatArray[$Key2][$Key1] = $StatArray[$Key1][$Key2];
            }
        }
        $NewStatArray[0][0] = '';
        unshift( @NewStatArray, [$Title] );
        @StatArray = @NewStatArray;
    }

    $Kernel::OM->ObjectParamAdd(
        'Kernel::Output::HTML::Statistics::View' => {
            StatsObject => $Self->{StatsObject},
        },
    );
    return $Kernel::OM->Get('Kernel::Output::HTML::Statistics::View')->RenderStatisticsResultData(
        StatArray => \@StatArray,
        Stat      => $Stat,
        %Param
    );

    return
}

sub GeneralSpecificationsWidgetAJAX {

    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    return $LayoutObject->Attachment(
        ContentType => 'text/html',
        Content     => $Self->_GeneralSpecificationsWidget(),
        Type        => 'inline',
        NoCache     => 1,
    );
}

sub _GeneralSpecificationsWidget {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    my $Stat;
    if ( $Param{StatID} ) {
        $Stat = $Self->{StatsObject}->StatsGet( StatID => $Param{StatID} );
    }
    else {
        $Stat->{StatID}     = 'new';
        $Stat->{StatNumber} = '';
        $Stat->{Valid}      = 1;
    }

    my %Frontend;

    # create selectboxes 'Cache', 'SumRow', 'SumCol', and 'Valid'
    for my $Key (qw(Cache ShowAsDashboardWidget SumRow SumCol)) {
        $Frontend{ 'Select' . $Key } = $LayoutObject->BuildSelection(
            Data => {
                0 => 'No',
                1 => 'Yes'
            },
            SelectedID => $Stat->{$Key} || 0,
            Name => $Key,
        );
    }

    # If this is a new stat, assume that it does not support the dashboard widget at the start.
    #   This is corrected by a call to AJAXUpdate when the page loads and when the user makes changes.
    if ( $Stat->{StatID} eq 'new' || !$Stat->{ObjectBehaviours}->{ProvidesDashboardWidget} ) {
        $Frontend{'SelectShowAsDashboardWidget'} = $LayoutObject->BuildSelection(
            Data => {
                0 => 'No (not supported)',
            },
            SelectedID => 0,
            Name       => 'ShowAsDashboardWidget',
        );
    }

    $Frontend{SelectValid} = $LayoutObject->BuildSelection(
        Data => {
            0 => 'invalid',
            1 => 'valid',
        },
        SelectedID => $Stat->{Valid},
        Name       => 'Valid',
    );

    # create multiselectboxes 'permission'
    my %Permission = (
        Data        => { $Kernel::OM->Get('Kernel::System::Group')->GroupList( Valid => 1 ) },
        Name        => 'Permission',
        Class       => 'Validate_Required',
        Multiple    => 1,
        Size        => 5,
        Translation => 0,
    );
    if ( $Stat->{Permission} ) {
        $Permission{SelectedID} = $Stat->{Permission};
    }
    else {
        $Permission{SelectedValue} = $ConfigObject->Get('Stats::DefaultSelectedPermissions');
    }
    $Stat->{SelectPermission} = $LayoutObject->BuildSelection(%Permission);

    # create multiselectboxes 'format'
    my $GDAvailable;
    my $AvailableFormats = $ConfigObject->Get('Stats::Format');

    # check availability of packages
    for my $Module ( 'GD', 'GD::Graph' ) {
        $GDAvailable = ( $Kernel::OM->Get('Kernel::System::Main')->Require($Module) ) ? 1 : 0;
    }

    # if the GD package is not installed, all the graph options will be disabled
    if ( !$GDAvailable ) {
        my @FormatData = map {
            Key          => $_,
                Value    => $AvailableFormats->{$_},
                Disabled => ( ( $_ =~ m/GD/gi ) ? 1 : 0 ),
        }, keys %{$AvailableFormats};

        $AvailableFormats = \@FormatData;
        $LayoutObject->Block( Name => 'PackageUnavailableMsg' );
    }

    $Stat->{SelectFormat} = $LayoutObject->BuildSelection(
        Data       => $AvailableFormats,
        Name       => 'Format',
        Class      => 'Validate_Required',
        Multiple   => 1,
        Size       => 5,
        SelectedID => $Stat->{Format}
            || $ConfigObject->Get('Stats::DefaultSelectedFormat'),
    );

    # create multiselectboxes 'graphsize'
    $Stat->{SelectGraphSize} = $LayoutObject->BuildSelection(
        Data        => $ConfigObject->Get('Stats::GraphSize'),
        Name        => 'GraphSize',
        Multiple    => 1,
        Size        => 3,
        SelectedID  => $Stat->{GraphSize},
        Translation => 0,
        Disabled    => ( first { $_ =~ m{^GD::}smx } @{ $Stat->{GraphSize} } ) ? 0 : 1,
    );

    my $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentStatistics/GeneralSpecificationsWidget',
        Data         => {
            %Frontend,
            %{$Stat},
        },
    );
    return $Output;
}

=item _ColumnAndRowTranslation()

translate the column and row name if needed

    $StatsObject->_ColumnAndRowTranslation(
        StatArrayRef => $StatArrayRef,
        HeadArrayRef => $HeadArrayRef,
        StatRef      => $StatRef,
        ExchangeAxis => 1 | 0,
    );

=cut

sub _ColumnAndRowTranslation {
    my ( $Self, %Param ) = @_;

    # check if need params are available
    for my $NeededParam (qw(StatArrayRef HeadArrayRef StatRef)) {
        if ( !$Param{$NeededParam} ) {
            return $Kernel::OM->Get('Kernel::Output::HTML::Layout')->ErrorScreen(
                Message => "_ColumnAndRowTranslation: Need $NeededParam!"
            );
        }
    }

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # create language object
    $Kernel::OM->ObjectParamAdd(
        'Kernel::Language' => {
            UserLanguage => $Param{UserLanguage} || $ConfigObject->Get('DefaultLanguage') || 'en',
            }
    );
    my $LanguageObject = $Kernel::OM->Get('Kernel::Language');

    # find out, if the column or row names should be translated
    my %Translation;
    my %Sort;

    for my $Use (qw( UseAsXvalue UseAsValueSeries )) {
        if (
            $Param{StatRef}->{StatType} eq 'dynamic'
            && $Param{StatRef}->{$Use}
            && ref( $Param{StatRef}->{$Use} ) eq 'ARRAY'
            )
        {
            my @Array = @{ $Param{StatRef}->{$Use} };

            ELEMENT:
            for my $Element (@Array) {
                next ELEMENT if !$Element->{SelectedValues};

                if ( $Element->{Translation} && $Element->{Block} eq 'Time' ) {
                    $Translation{$Use} = 'Time';
                }
                elsif ( $Element->{Translation} ) {
                    $Translation{$Use} = 'Common';
                }
                else {
                    $Translation{$Use} = '';
                }

                if (
                    $Element->{Translation}
                    && $Element->{Block} ne 'Time'
                    && !$Element->{SortIndividual}
                    )
                {
                    $Sort{$Use} = 1;
                }
                last ELEMENT;
            }
        }
    }

    # check if the axis are changed
    if ( $Param{ExchangeAxis} ) {
        my $UseAsXvalueOld = $Translation{UseAsXvalue};
        $Translation{UseAsXvalue}      = $Translation{UseAsValueSeries};
        $Translation{UseAsValueSeries} = $UseAsXvalueOld;

        my $SortUseAsXvalueOld = $Sort{UseAsXvalue};
        $Sort{UseAsXvalue}      = $Sort{UseAsValueSeries};
        $Sort{UseAsValueSeries} = $SortUseAsXvalueOld;
    }

    # translate the headline
    $Param{HeadArrayRef}->[0] = $LanguageObject->Translate( $Param{HeadArrayRef}->[0] );

    if ( $Translation{UseAsXvalue} && $Translation{UseAsXvalue} eq 'Time' ) {
        for my $Word ( @{ $Param{HeadArrayRef} } ) {
            if ( $Word =~ m{ ^ (\w+?) ( \s \d+ ) $ }smx ) {
                my $TranslatedWord = $LanguageObject->Translate($1);
                $Word =~ s{ ^ ( \w+? ) ( \s \d+ ) $ }{$TranslatedWord$2}smx;
            }
        }
    }

    elsif ( $Translation{UseAsXvalue} ) {
        for my $Word ( @{ $Param{HeadArrayRef} } ) {
            $Word = $LanguageObject->Translate($Word);
        }
    }

    # sort the headline
    if ( $Sort{UseAsXvalue} ) {
        my @HeadOld = @{ $Param{HeadArrayRef} };
        shift @HeadOld;    # because the first value is no sortable column name

        # special handling if the sumfunction is used
        my $SumColRef;
        if ( $Param{StatRef}->{SumRow} ) {
            $SumColRef = pop @HeadOld;
        }

        # sort
        my @SortedHead = sort { $a cmp $b } @HeadOld;

        # special handling if the sumfunction is used
        if ( $Param{StatRef}->{SumCol} ) {
            push @SortedHead, $SumColRef;
            push @HeadOld,    $SumColRef;
        }

        # add the row names to the new StatArray
        my @StatArrayNew;
        for my $Row ( @{ $Param{StatArrayRef} } ) {
            push @StatArrayNew, [ $Row->[0] ];
        }

        # sort the values
        for my $ColumnName (@SortedHead) {
            my $Counter = 0;
            COLUMNNAMEOLD:
            for my $ColumnNameOld (@HeadOld) {
                $Counter++;
                next COLUMNNAMEOLD if $ColumnNameOld ne $ColumnName;

                for my $RowLine ( 0 .. $#StatArrayNew ) {
                    push @{ $StatArrayNew[$RowLine] }, $Param{StatArrayRef}->[$RowLine]->[$Counter];
                }
                last COLUMNNAMEOLD;
            }
        }

        # bring the data back to the references
        unshift @SortedHead, $Param{HeadArrayRef}->[0];
        @{ $Param{HeadArrayRef} } = @SortedHead;
        @{ $Param{StatArrayRef} } = @StatArrayNew;
    }

    # translate the row description
    if ( $Translation{UseAsValueSeries} && $Translation{UseAsValueSeries} eq 'Time' ) {
        for my $Word ( @{ $Param{StatArrayRef} } ) {
            if ( $Word->[0] =~ m{ ^ (\w+?) ( \s \d+ ) $ }smx ) {
                my $TranslatedWord = $LanguageObject->Translate($1);
                $Word->[0] =~ s{ ^ ( \w+? ) ( \s \d+ ) $ }{$TranslatedWord$2}smx;
            }
        }
    }
    elsif ( $Translation{UseAsValueSeries} ) {

        # translate
        for my $Word ( @{ $Param{StatArrayRef} } ) {
            $Word->[0] = $LanguageObject->Translate( $Word->[0] );
        }
    }

    # sort the row description
    if ( $Sort{UseAsValueSeries} ) {

        # special handling if the sumfunction is used
        my $SumRowArrayRef;
        if ( $Param{StatRef}->{SumRow} ) {
            $SumRowArrayRef = pop @{ $Param{StatArrayRef} };
        }

        # sort
        my $DisableDefaultResultSort = grep {
            $_->{DisableDefaultResultSort}
                && $_->{DisableDefaultResultSort} == 1
        } @{ $Param{StatRef}->{UseAsXvalue} };

        if ( !$DisableDefaultResultSort ) {
            @{ $Param{StatArrayRef} } = sort { $a->[0] cmp $b->[0] } @{ $Param{StatArrayRef} };
        }

        # special handling if the sumfunction is used
        if ( $Param{StatRef}->{SumRow} ) {
            push @{ $Param{StatArrayRef} }, $SumRowArrayRef;
        }
    }

    return 1;
}

# ATTENTION: this function delivers only approximations!!!
sub _TimeInSeconds {
    my ( $Self, %Param ) = @_;

    # check if need params are available
    if ( !$Param{TimeUnit} ) {
        return $Kernel::OM->Get('Kernel::Output::HTML::Layout')
            ->ErrorScreen( Message => '_TimeInSeconds: Need TimeUnit!' );
    }

    my %TimeInSeconds = (
        Year   => 31536000,    # 60 * 60 * 60 * 365
        Month  => 2592000,     # 60 * 60 * 24 * 30
        Week   => 604800,      # 60 * 60 * 24 * 7
        Day    => 86400,       # 60 * 60 * 24
        Hour   => 3600,        # 60 * 60
        Minute => 60,
        Second => 1,
    );

    return $TimeInSeconds{ $Param{TimeUnit} };
}

1;
