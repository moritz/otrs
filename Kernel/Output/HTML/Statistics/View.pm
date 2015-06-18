# --
# Copyright (C) 2001-2015 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Output::HTML::Statistics::View;

## nofilter(TidyAll::Plugin::OTRS::Perl::PodChecker)

use strict;
use warnings;

use List::Util qw( first );

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::Language',
    'Kernel::Output::HTML::Layout',
    'Kernel::System::CSV',
    'Kernel::System::Group',
    'Kernel::System::Log',
    'Kernel::System::Main',
    'Kernel::System::PDF',
    'Kernel::System::Stats',
    'Kernel::System::Ticket',
    'Kernel::System::Time',
    'Kernel::System::User',
    'Kernel::System::Web::Request',
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    $Self->{StatsObject} = $Param{StatsObject} || die 'Need StatsObject!';

    return $Self;
}

sub StatsViewParameterWidget {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # check if need params are available
    for my $Needed (qw(Stat)) {
        if ( !$Param{$Needed} ) {
            return $LayoutObject->ErrorScreen( Message => "Need $Needed!" );
        }
    }

    my $Stat   = $Param{Stat};
    my $StatID = $Stat->{StatID};

    my $Output;

    # get the object name
    if ( $Stat->{StatType} eq 'static' ) {
        $Stat->{ObjectName} = $Stat->{File};
    }

    # if no object name is defined use an empty string
    $Stat->{ObjectName} ||= '';

    # create format select box
    my %SelectFormat;
    my $Flag    = 0;
    my $Counter = 0;
    my $Format  = $ConfigObject->Get('Stats::Format');
    for my $UseAsValueSeries ( @{ $Stat->{UseAsValueSeries} } ) {
        if ( $UseAsValueSeries->{Selected} ) {
            $Counter++;
        }
    }
    my $CounterII = 0;
    for my $Value ( @{ $Stat->{Format} } ) {
        if ( $Counter == 0 || $Value ne 'GD::Graph::pie' ) {
            $SelectFormat{$Value} = $Format->{$Value};
            $CounterII++;
        }
        if ( $Value =~ m{^GD::Graph\.*}x ) {
            $Flag = 1;
        }
    }
    if ( $CounterII > 1 ) {
        my %Frontend;
        $Frontend{SelectFormat} = $LayoutObject->BuildSelection(
            Data => \%SelectFormat,
            Name => 'Format',
        );
        $LayoutObject->Block(
            Name => 'Format',
            Data => \%Frontend,
        );
    }
    else {
        $LayoutObject->Block(
            Name => 'FormatFixed',
            Data => {
                Format    => $Format->{ $Stat->{Format}->[0] },
                FormatKey => $Stat->{Format}->[0],
            },
        );
    }

    # create graphic size select box
    if ( $Stat->{GraphSize} && $Flag ) {
        my %GraphSize;
        my %Frontend;
        my $GraphSizeRef = $ConfigObject->Get('Stats::GraphSize');
        for my $Value ( @{ $Stat->{GraphSize} } ) {
            $GraphSize{$Value} = $GraphSizeRef->{$Value};
        }
        if ( $#{ $Stat->{GraphSize} } > 0 ) {
            $Frontend{SelectGraphSize} = $LayoutObject->BuildSelection(
                Data        => \%GraphSize,
                Name        => 'GraphSize',
                Translation => 0,
            );
            $LayoutObject->Block(
                Name => 'Graphsize',
                Data => \%Frontend,
            );
        }
        else {
            $LayoutObject->Block(
                Name => 'GraphsizeFixed',
                Data => {
                    GraphSize    => $GraphSizeRef->{ $Stat->{GraphSize}->[0] },
                    GraphSizeKey => $Stat->{GraphSize}->[0],
                },
            );
        }
    }

    if ( $ConfigObject->Get('Stats::ExchangeAxis') ) {
        my $ExchangeAxis = $LayoutObject->BuildSelection(
            Data => {
                1 => 'Yes',
                0 => 'No'
            },
            Name       => 'ExchangeAxis',
            SelectedID => 0,
        );

        $LayoutObject->Block(
            Name => 'ExchangeAxis',
            Data => { ExchangeAxis => $ExchangeAxis }
        );
    }

    # get static attributes
    if ( $Stat->{StatType} eq 'static' ) {

        # load static module
        my $Params = $Self->{StatsObject}->GetParams( StatID => $StatID );
        $LayoutObject->Block(
            Name => 'Static',
        );
        PARAMITEM:
        for my $ParamItem ( @{$Params} ) {
            next PARAMITEM if $ParamItem->{Name} eq 'GraphSize';
            $LayoutObject->Block(
                Name => 'ItemParam',
                Data => {
                    Param => $ParamItem->{Frontend},
                    Name  => $ParamItem->{Name},
                    Field => $LayoutObject->BuildSelection(
                        Data       => $ParamItem->{Data},
                        Name       => $ParamItem->{Name},
                        SelectedID => $ParamItem->{SelectedID} || '',
                        Multiple   => $ParamItem->{Multiple} || 0,
                        Size       => $ParamItem->{Size} || '',
                    ),
                },
            );
        }
    }

    # get dynamic attributes
    elsif ( $Stat->{StatType} eq 'dynamic' ) {
        my %Name = (
            UseAsXvalue      => 'X-axis',
            UseAsValueSeries => 'Value Series',
            UseAsRestriction => 'Restrictions',
        );

        for my $Use (qw(UseAsXvalue UseAsValueSeries UseAsRestriction)) {
            my $Flag = 0;
            $LayoutObject->Block(
                Name => 'Dynamic',
                Data => { Name => $Name{$Use} },
            );
            OBJECTATTRIBUTE:
            for my $ObjectAttribute ( @{ $Stat->{$Use} } ) {
                next OBJECTATTRIBUTE if !$ObjectAttribute->{Selected};

                my %ValueHash;
                $Flag = 1;

                # Select All function
                if ( !$ObjectAttribute->{SelectedValues}[0] ) {
                    if (
                        $ObjectAttribute->{Values} && ref $ObjectAttribute->{Values} ne 'HASH'
                        )
                    {
                        $Kernel::OM->Get('Kernel::System::Log')->Log(
                            Priority => 'error',
                            Message  => 'Values needs to be a hash reference!'
                        );
                        next OBJECTATTRIBUTE;
                    }
                    my @Values = keys( %{ $ObjectAttribute->{Values} } );
                    $ObjectAttribute->{SelectedValues} = \@Values;
                }
                for ( @{ $ObjectAttribute->{SelectedValues} } ) {
                    if ( $ObjectAttribute->{Values} ) {
                        $ValueHash{$_} = $ObjectAttribute->{Values}{$_};
                    }
                    else {
                        $ValueHash{Value} = $_;
                    }
                }

                $LayoutObject->Block(
                    Name => 'Element',
                    Data => { Name => $ObjectAttribute->{Name} },
                );

                # show fixed elements
                if ( $ObjectAttribute->{Fixed} ) {
                    if ( $ObjectAttribute->{Block} eq 'Time' ) {
                        if ( $Use eq 'UseAsRestriction' ) {
                            delete $ObjectAttribute->{SelectedValues};
                        }
                        my $TimeScale = _TimeScale();
                        if ( $ObjectAttribute->{TimeStart} ) {
                            $LayoutObject->Block(
                                Name => 'TimePeriodFixed',
                                Data => {
                                    TimeStart => $ObjectAttribute->{TimeStart},
                                    TimeStop  => $ObjectAttribute->{TimeStop},
                                },
                            );
                        }
                        elsif ( $ObjectAttribute->{TimeRelativeUnit} ) {
                            $LayoutObject->Block(
                                Name => 'TimeRelativeFixed',
                                Data => {
                                    TimeRelativeUnit =>
                                        $TimeScale->{ $ObjectAttribute->{TimeRelativeUnit} }
                                        {Value},
                                    TimeRelativeCount => $ObjectAttribute->{TimeRelativeCount},
                                },
                            );
                        }
                        if ( $ObjectAttribute->{SelectedValues}[0] ) {
                            $LayoutObject->Block(
                                Name => 'TimeScaleFixed',
                                Data => {
                                    Scale =>
                                        $TimeScale->{ $ObjectAttribute->{SelectedValues}[0] }
                                        {Value},
                                    Count => $ObjectAttribute->{TimeScaleCount},
                                },
                            );
                        }
                    }
                    else {

                        # find out which sort mechanism is used
                        my @Sorted;
                        if ( $ObjectAttribute->{SortIndividual} ) {
                            @Sorted = grep { $ValueHash{$_} }
                                @{ $ObjectAttribute->{SortIndividual} };
                        }
                        else {
                            @Sorted = sort { $ValueHash{$a} cmp $ValueHash{$b} } keys %ValueHash;
                        }

                        for (@Sorted) {
                            my $Value = $ValueHash{$_};
                            if ( $ObjectAttribute->{Translation} ) {
                                $Value = $LayoutObject->{LanguageObject}->Translate( $ValueHash{$_} );
                            }
                            $LayoutObject->Block(
                                Name => 'Fixed',
                                Data => {
                                    Value   => $Value,
                                    Key     => $_,
                                    Use     => $Use,
                                    Element => $ObjectAttribute->{Element},
                                },
                            );
                        }
                    }
                }

                # show  unfixed elements
                else {
                    my %BlockData;
                    $BlockData{Name}    = $ObjectAttribute->{Name};
                    $BlockData{Element} = $ObjectAttribute->{Element};
                    $BlockData{Value}   = $ObjectAttribute->{SelectedValues}->[0];

                    if ( $ObjectAttribute->{Block} eq 'MultiSelectField' ) {
                        $BlockData{SelectField} = $LayoutObject->BuildSelection(
                            Data           => \%ValueHash,
                            Name           => $Use . $ObjectAttribute->{Element},
                            Multiple       => 1,
                            Size           => 5,
                            SelectedID     => $ObjectAttribute->{SelectedValues},
                            Translation    => $ObjectAttribute->{Translation},
                            TreeView       => $ObjectAttribute->{TreeView} || 0,
                            Sort           => $ObjectAttribute->{Sort} || undef,
                            SortIndividual => $ObjectAttribute->{SortIndividual} || undef,
                        );
                        $LayoutObject->Block(
                            Name => 'MultiSelectField',
                            Data => \%BlockData,
                        );
                    }
                    elsif ( $ObjectAttribute->{Block} eq 'SelectField' ) {

                        $BlockData{SelectField} = $LayoutObject->BuildSelection(
                            Data           => \%ValueHash,
                            Name           => $Use . $ObjectAttribute->{Element},
                            Translation    => $ObjectAttribute->{Translation},
                            TreeView       => $ObjectAttribute->{TreeView} || 0,
                            Sort           => $ObjectAttribute->{Sort} || undef,
                            SortIndividual => $ObjectAttribute->{SortIndividual} || undef,
                        );
                        $LayoutObject->Block(
                            Name => 'SelectField',
                            Data => \%BlockData,
                        );
                    }

                    elsif ( $ObjectAttribute->{Block} eq 'InputField' ) {
                        $LayoutObject->Block(
                            Name => 'InputField',
                            Data => {
                                Key   => $Use . $ObjectAttribute->{Element},
                                Value => $ObjectAttribute->{SelectedValues}[0],
                            },
                        );
                    }
                    elsif ( $ObjectAttribute->{Block} eq 'Time' ) {
                        $ObjectAttribute->{Element} = $Use . $ObjectAttribute->{Element};
                        my $TimeType = $ConfigObject->Get('Stats::TimeType')
                            || 'Normal';
                        my %TimeData = _Timeoutput(
                            $Self, %{$ObjectAttribute},
                            OnlySelectedAttributes => 1
                        );
                        %BlockData = ( %BlockData, %TimeData );
                        if ( $ObjectAttribute->{TimeStart} ) {
                            $BlockData{TimeStartMax} = $ObjectAttribute->{TimeStart};
                            $BlockData{TimeStopMax}  = $ObjectAttribute->{TimeStop};
                            $LayoutObject->Block(
                                Name => 'TimePeriod',
                                Data => \%BlockData,
                            );
                        }

                        elsif ( $ObjectAttribute->{TimeRelativeUnit} ) {
                            my $TimeScale = _TimeScale();
                            if ( $TimeType eq 'Extended' ) {
                                my %TimeScaleOption;
                                ITEM:
                                for (
                                    sort {
                                        $TimeScale->{$a}->{Position}
                                            <=> $TimeScale->{$b}->{Position}
                                    } keys %{$TimeScale}
                                    )
                                {
                                    $TimeScaleOption{$_} = $TimeScale->{$_}{Value};
                                    last ITEM if $ObjectAttribute->{TimeRelativeUnit} eq $_;
                                }
                                $BlockData{TimeRelativeUnit} = $LayoutObject->BuildSelection(
                                    Name           => $ObjectAttribute->{Element} . 'TimeRelativeUnit',
                                    Data           => \%TimeScaleOption,
                                    Sort           => 'IndividualKey',
                                    SelectedID     => $ObjectAttribute->{TimeRelativeUnit},
                                    SortIndividual => [
                                        'Second', 'Minute', 'Hour', 'Day',
                                        'Week', 'Month', 'Year'
                                    ],
                                );
                            }
                            $BlockData{TimeRelativeCountMax} = $ObjectAttribute->{TimeRelativeCount};
                            $BlockData{TimeRelativeUnitMax}
                                = $TimeScale->{ $ObjectAttribute->{TimeRelativeUnit} }{Value};

                            $LayoutObject->Block(
                                Name => 'TimePeriodRelative',
                                Data => \%BlockData,
                            );
                        }

                        # build the Timescale output
                        if ( $Use ne 'UseAsRestriction' ) {
                            if ( $TimeType eq 'Normal' ) {
                                $BlockData{TimeScaleCount} = 1;
                                $BlockData{TimeScaleUnit}  = $BlockData{TimeSelectField};
                            }
                            elsif ( $TimeType eq 'Extended' ) {
                                my $TimeScale = _TimeScale();
                                my %TimeScaleOption;
                                ITEM:
                                for (
                                    sort {
                                        $TimeScale->{$b}->{Position}
                                            <=> $TimeScale->{$a}->{Position}
                                    } keys %{$TimeScale}
                                    )
                                {
                                    $TimeScaleOption{$_} = $TimeScale->{$_}->{Value};
                                    last ITEM if $ObjectAttribute->{SelectedValues}[0] eq $_;
                                }
                                $BlockData{TimeScaleUnitMax} = $TimeScale->{ $ObjectAttribute->{SelectedValues}[0] }
                                    {Value};
                                $BlockData{TimeScaleCountMax} = $ObjectAttribute->{TimeScaleCount};

                                $BlockData{TimeScaleUnit} = $LayoutObject->BuildSelection(
                                    Name           => $ObjectAttribute->{Element},
                                    Data           => \%TimeScaleOption,
                                    SelectedID     => $ObjectAttribute->{SelectedValues}[0],
                                    Sort           => 'IndividualKey',
                                    SortIndividual => [
                                        'Second', 'Minute', 'Hour', 'Day',
                                        'Week', 'Month', 'Year'
                                    ],
                                );
                                $LayoutObject->Block(
                                    Name => 'TimeScaleInfo',
                                    Data => \%BlockData,
                                );
                            }
                            if ( $ObjectAttribute->{SelectedValues} ) {
                                $LayoutObject->Block(
                                    Name => 'TimeScale',
                                    Data => \%BlockData,
                                );
                                if ( $BlockData{TimeScaleUnitMax} ) {
                                    $LayoutObject->Block(
                                        Name => 'TimeScaleInfo',
                                        Data => \%BlockData,
                                    );
                                }
                            }
                        }

                        # end of build timescale output
                    }
                }
            }

            # Show this Block if no value series or restrictions are selected
            if ( !$Flag ) {
                $LayoutObject->Block(
                    Name => 'NoElement',
                );
            }
        }
    }
    my %YesNo = (
        0 => 'No',
        1 => 'Yes'
    );
    my %ValidInvalid = (
        0 => 'invalid',
        1 => 'valid'
    );
    $Stat->{SumRowValue}                = $YesNo{ $Stat->{SumRow} };
    $Stat->{SumColValue}                = $YesNo{ $Stat->{SumCol} };
    $Stat->{CacheValue}                 = $YesNo{ $Stat->{Cache} };
    $Stat->{ShowAsDashboardWidgetValue} = $YesNo{ $Stat->{ShowAsDashboardWidget} // 0 };
    $Stat->{ValidValue}                 = $ValidInvalid{ $Stat->{Valid} };

    for (qw(CreatedBy ChangedBy)) {
        $Stat->{$_} = $Kernel::OM->Get('Kernel::System::User')->UserName( UserID => $Stat->{$_} );
    }

    # # store last screen
    # $SessionObject->UpdateSessionID(
    #     SessionID => $Self->{SessionID},
    #     Key       => 'LastStatsView',
    #     Value     => $Self->{RequestedURL},
    # );

    # Completeness check
    my @Notify = $Self->{StatsObject}->CompletenessCheck(
        StatData => $Stat,
        Section  => 'All'
    );

    # show the start button if the stat is valid and completeness check true
    if ( $Stat->{Valid} && !@Notify ) {
        $LayoutObject->Block(
            Name => 'FormSubmit',
            Data => $Stat,
        );
    }

    # check if the PDF module is installed and enabled
    if ( $ConfigObject->Get('PDF') ) {
        $Stat->{PDFUsable} = $Kernel::OM->Get('Kernel::System::PDF') ? 1 : 0;
    }

    # Error message if there is an invalid setting in the search mask
    # in need of better solution

    my $Message = $Kernel::OM->Get('Kernel::System::Web::Request')->GetParam( Param => 'Message' );

    if ($Message) {
        my %ErrorMessages = (
            1 => 'The selected start time is before the allowed start time!',
            2 => 'The selected end time is later than the allowed end time!',
            3 => 'The selected time period is larger than the allowed time period!',
            4 => 'Your reporting time interval is too small, please use a larger time scale!',
        );

        $Output .= $LayoutObject->Notify(
            Info     => $ErrorMessages{$Message},
            Priority => 'Error',
        );
    }

    # Show warning if restrictions contain stop words within ticket search.
    if (
        $Stat->{UseAsRestriction}
        && ref $Stat->{UseAsRestriction} eq 'ARRAY'
        && $Kernel::OM->Get('Kernel::System::Ticket')->SearchStringStopWordsUsageWarningActive()
        )
    {
        my %StopWordFields = $Self->_StopWordFieldsGet();
        my %StopWordStrings;

        RESTRICTION:
        for my $Restriction ( @{ $Stat->{UseAsRestriction} } ) {
            next RESTRICTION if !$Restriction->{Name};
            next RESTRICTION if !$StopWordFields{ $Restriction->{Name} };
            next RESTRICTION if !$Restriction->{SelectedValues};
            next RESTRICTION if ref $Restriction->{SelectedValues} ne 'ARRAY';

            for my $StopWordString ( @{ $Restriction->{SelectedValues} } ) {
                $StopWordStrings{ $Restriction->{Name} } = $StopWordString;
            }
        }

        if (%StopWordStrings) {
            my %StopWordsServerErrors = $Self->_StopWordsServerErrorsGet(%StopWordStrings);
            if (%StopWordsServerErrors) {
                my $Info = $LayoutObject->{LanguageObject}->Translate(
                    'Please check restrictions of this stat for errors.'
                );

                $Output .= $LayoutObject->Notify(
                    Info     => $Info,
                    Priority => 'Error',
                );
            }
        }
    }

    $Output .= $Self->_Notify(
        StatData => $Stat,
        Section  => 'All'
    );

    $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentStatistics/StatsViewParameterWidget',
        Data         => {

            #%Frontend,
            %{$Stat},
        },
    );
    return $Output;
}

sub GeneralSpecificationsWidget {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # In case of page reload because of errors
    my %Errors   = %{ $Param{Errors}   // {} };
    my %GetParam = %{ $Param{GetParam} // {} };

    my $Stat;
    if ( $Param{StatID} ) {
        $Stat = $Self->{StatsObject}->StatsGet( StatID => $Param{StatID} );
    }
    else {
        $Stat->{StatID}     = '';
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
            SelectedID => $GetParam{$Key} // $Stat->{$Key} || 0,
            Name => $Key,
        );
    }

    # If this is a new stat, assume that it does not support the dashboard widget at the start.
    #   This is corrected by a call to AJAXUpdate when the page loads and when the user makes changes.
    if ( !$Stat->{StatID} || !$Stat->{ObjectBehaviours}->{ProvidesDashboardWidget} ) {
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
        SelectedID => $GetParam{Valid} // $Stat->{Valid},
        Name => 'Valid',
    );

    # Create a new statistic
    if ( !$Stat->{StatType} ) {
        my $DynamicFiles = $Self->{StatsObject}->GetDynamicFiles();

        my %ObjectModules;
        DYNAMIC_FILE:
        for my $DynamicFile ( sort keys %{ $DynamicFiles // {} } ) {
            my $ObjectName = 'Kernel::System::Stats::Dynamic::' . $DynamicFile;

            next DYNAMIC_FILE if !$Kernel::OM->Get('Kernel::System::Main')->Require($ObjectName);
            my $Object = $ObjectName->new();
            next DYNAMIC_FILE if !$Object;
            if ( $Object->can('GetStatElement') ) {
                $ObjectModules{DynamicMatrix}->{$ObjectName} = $DynamicFiles->{$DynamicFile};
            }
            else {
                $ObjectModules{DynamicList}->{$ObjectName} = $DynamicFiles->{$DynamicFile};
            }
        }

        my $StaticFiles = $Self->{StatsObject}->GetStaticFiles(
            OnlyUnusedFiles => 1,
        );
        for my $StaticFile ( sort keys %{ $StaticFiles // {} } ) {
            $ObjectModules{Static}->{ 'Kernel::System::Stats::Static::' . $StaticFile } = $StaticFiles->{$StaticFile};
        }

        $Frontend{StatisticPreselection} = $ParamObject->GetParam( Param => 'StatisticPreselection' );

        if ( $Frontend{StatisticPreselection} eq 'Static' ) {
            $Frontend{StatType}         = 'static';
            $Frontend{SelectObjectType} = $LayoutObject->BuildSelection(
                Data        => $ObjectModules{Static},
                Name        => 'ObjectModule',
                Class       => 'Validate_Required' . ( $Errors{ObjectModuleServerError} ? ' ServerError' : '' ),
                Translation => 0,
                SelectedID  => $GetParam{ObjectModule},
            );
        }
        elsif ( $Frontend{StatisticPreselection} eq 'DynamicList' ) {
            $Frontend{StatType}         = 'dynamic';
            $Frontend{SelectObjectType} = $LayoutObject->BuildSelection(
                Data        => $ObjectModules{DynamicList},
                Name        => 'ObjectModule',
                Translation => 1,
                Class       => ( $Errors{ObjectModuleServerError} ? ' ServerError' : '' ),
                SelectedID => $GetParam{ObjectModule} // $ConfigObject->Get('Stats::DefaultSelectedDynamicObject'),
            );
        }

        # DynamicMatrix
        else {
            $Frontend{StatType}         = 'dynamic';
            $Frontend{SelectObjectType} = $LayoutObject->BuildSelection(
                Data        => $ObjectModules{DynamicMatrix},
                Name        => 'ObjectModule',
                Translation => 1,
                Class       => ( $Errors{ObjectModuleServerError} ? ' ServerError' : '' ),
                SelectedID => $GetParam{ObjectModule} // $ConfigObject->Get('Stats::DefaultSelectedDynamicObject'),
            );

        }

        #use Data::Dumper;
        #print STDERR Dumper(\$Frontend{SelectObjectType});

    }

    # create multiselectboxes 'permission'
    my %Permission = (
        Data => { $Kernel::OM->Get('Kernel::System::Group')->GroupList( Valid => 1 ) },
        Name => 'Permission',
        Class => 'Validate_Required' . ( $Errors{PermissionServerError} ? ' ServerError' : '' ),
        Multiple    => 1,
        Size        => 5,
        Translation => 0,
    );
    if ( $GetParam{Permission} // $Stat->{Permission} ) {
        $Permission{SelectedID} = $GetParam{Permission} // $Stat->{Permission};
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
        Data     => $AvailableFormats,
        Name     => 'Format',
        Class    => 'Validate_Required' . ( $Errors{FormatServerError} ? ' ServerError' : '' ),
        Multiple => 1,
        Size     => 5,
        SelectedID => $GetParam{Format} // $Stat->{Format} || $ConfigObject->Get('Stats::DefaultSelectedFormat'),
    );

    # create multiselectboxes 'graphsize'
    $Stat->{SelectGraphSize} = $LayoutObject->BuildSelection(
        Data        => $ConfigObject->Get('Stats::GraphSize'),
        Name        => 'GraphSize',
        Multiple    => 1,
        Size        => 3,
        SelectedID  => $GetParam{GraphSize} // $Stat->{GraphSize},
        Translation => 0,
        Disabled    => ( first { $_ =~ m{^GD::}smx } @{ $Stat->{GraphSize} } ) ? 0 : 1,
    );

    my $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentStatistics/GeneralSpecificationsWidget',
        Data         => {
            %Frontend,
            %{$Stat},
            %GetParam,
            %Errors,
        },
    );
    return $Output;
}

sub XAxisWidget {
    my ( $Self, %Param ) = @_;

    my $Stat = $Param{Stat};

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    #my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # if only one value is available select this value
    if ( !$Stat->{UseAsXvalue}[0]{Selected} && scalar( @{ $Stat->{UseAsXvalue} } ) == 1 ) {
        $Stat->{UseAsXvalue}[0]{Selected} = 1;
        $Stat->{UseAsXvalue}[0]{Fixed}    = 1;
    }

    for my $ObjectAttribute ( @{ $Stat->{UseAsXvalue} } ) {
        my %BlockData;
        $BlockData{Fixed}   = 'checked="checked"';
        $BlockData{Checked} = '';

        # things which should be done if this attribute is selected
        if ( $ObjectAttribute->{Selected} ) {
            $BlockData{Checked} = 'checked="checked"';
            if ( !$ObjectAttribute->{Fixed} ) {
                $BlockData{Fixed} = '';
            }
        }

        if ( $ObjectAttribute->{Block} eq 'SelectField' ) {
            $ObjectAttribute->{Block} = 'MultiSelectField';
        }

        if ( $ObjectAttribute->{Block} eq 'MultiSelectField' ) {
            $BlockData{SelectField} = $LayoutObject->BuildSelection(
                Data     => $ObjectAttribute->{Values},
                Name     => 'XAxis' . $ObjectAttribute->{Element},
                Multiple => 1,
                Size     => 5,
                Class =>
                    ( $ObjectAttribute->{ShowAsTree} && $ObjectAttribute->{IsDynamicField} )
                ? 'DynamicFieldWithTreeView'
                : '',
                SelectedID     => $ObjectAttribute->{SelectedValues},
                Translation    => $ObjectAttribute->{Translation},
                TreeView       => $ObjectAttribute->{TreeView} || 0,
                Sort           => $ObjectAttribute->{Sort} || undef,
                SortIndividual => $ObjectAttribute->{SortIndividual} || undef,
            );

            if ( $ObjectAttribute->{ShowAsTree} && $ObjectAttribute->{IsDynamicField} ) {
                my $TreeSelectionMessage = $LayoutObject->{LanguageObject}->Translate("Show Tree Selection");
                $BlockData{SelectField}
                    .= ' <a href="#" title="'
                    . $TreeSelectionMessage
                    . '" class="ShowTreeSelection"><span>'
                    . $TreeSelectionMessage . '</span><i class="fa fa-sitemap"></i></a>';
            }
        }

        $BlockData{Name}    = $ObjectAttribute->{Name};
        $BlockData{Element} = 'XAxis' . $ObjectAttribute->{Element};

        # show the attribute block
        $LayoutObject->Block(
            Name => 'Attribute',
            Data => \%BlockData,
        );

        if ( $ObjectAttribute->{Block} eq 'Time' ) {
            my $TimeType = $ConfigObject->Get('Stats::TimeType') || 'Normal';
            if ( $TimeType eq 'Time' ) {
                $ObjectAttribute->{Block} = 'Time';
            }
            elsif ( $TimeType eq 'Extended' ) {
                $ObjectAttribute->{Block} = 'TimeExtended';
            }

            my %TimeData = _Timeoutput(
                $Self,
                %{$ObjectAttribute},
                Element => $BlockData{Element},
            );
            %BlockData = ( %BlockData, %TimeData );
        }

        # show the input element
        $LayoutObject->Block(
            Name => $ObjectAttribute->{Block},
            Data => \%BlockData,
        );
    }

    my $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentStatistics/XAxisWidget',
        Data         => {
            %{$Stat},
        },
    );
    return $Output;

}

sub PreviewContainer {
    my ( $Self, %Param ) = @_;

    my $Stat = $Param{Stat};

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    my $PreviewResult = $Self->{StatsObject}->StatsRun(
        StatID   => $Stat->{StatID},
        GetParam => $Stat,
    );

    my $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentStatistics/PreviewContainer',
        Data         => {

            #%Frontend,
            %{$Stat},
            PreviewResult => $PreviewResult,
        },
    );
    return $Output;
}

sub RenderStatisticsResultData {
    my ( $Self, %Param ) = @_;

    my @StatArray = @{ $Param{StatArray} // [] };
    my $Stat = $Param{Stat};

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    my $TitleArrayRef = shift @StatArray;
    my $Title         = $TitleArrayRef->[0];
    my $HeadArrayRef  = shift @StatArray;

    # if array = empty
    if ( !@StatArray ) {
        push @StatArray, [ ' ', 0 ];
    }

    # Generate Filename
    my $Filename = $Self->{StatsObject}->StringAndTimestamp2Filename(
        String => $Stat->{Title} . ' Created',
    );

    # Translate the column and row description
    $Self->_ColumnAndRowTranslation(
        StatArrayRef => \@StatArray,
        HeadArrayRef => $HeadArrayRef,
        StatRef      => $Stat,
        ExchangeAxis => $Param{ExchangeAxis},
    );
    my $Output;

    # get CSV object
    my $CSVObject = $Kernel::OM->Get('Kernel::System::CSV');

    # generate D3 output
    if ( $Param{Format} =~ m{^D3} ) {
        my $Output = $LayoutObject->Header( Value => $Title );
        $Output .= $LayoutObject->Output(
            Data => {
                %{$Stat},
                RawData => [
                    [$Title],
                    $HeadArrayRef,
                    @StatArray,
                ],
                %Param,
            },
            TemplateFile => 'AgentStatistics/RenderStatisticsResultData/D3',
        );
        $Output .= $LayoutObject->Footer();
        return $Output;
    }

    # generate csv output
    if ( $Param{Format} eq 'CSV' ) {

        # get Separator from language file
        my $UserCSVSeparator = $LayoutObject->{LanguageObject}->{Separator};

        if ( $ConfigObject->Get('PreferencesGroups')->{CSVSeparator}->{Active} ) {
            my %UserData = $$Kernel::OM->Get('Kernel::System::User')->GetUserData( UserID => $Self->{UserID} );
            $UserCSVSeparator = $UserData{UserCSVSeparator} if $UserData{UserCSVSeparator};
        }
        $Output .= $CSVObject->Array2CSV(
            Head      => $HeadArrayRef,
            Data      => \@StatArray,
            Separator => $UserCSVSeparator,
        );

        return $LayoutObject->Attachment(
            Filename    => $Filename . '.csv',
            ContentType => "text/csv",
            Content     => $Output,
        );
    }

    # generate excel output
    elsif ( $Param{Format} eq 'Excel' ) {
        $Output .= $CSVObject->Array2CSV(
            Head   => $HeadArrayRef,
            Data   => \@StatArray,
            Format => 'Excel',
        );

        return $LayoutObject->Attachment(
            Filename    => $Filename . '.xlsx',
            ContentType => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            Content     => $Output,
        );

    }

    # pdf or html output
    elsif ( $Param{Format} eq 'Print' ) {
        $Kernel::OM->Get('Kernel::System::Main')->Require('Kernel::System::PDF');

        # get PDF object
        my $PDFObject;

        if ( $ConfigObject->Get('PDF') ) {
            $PDFObject = $Kernel::OM->Get('Kernel::System::PDF');
        }

        # PDF Output
        if ($PDFObject) {
            my $PrintedBy = $LayoutObject->{LanguageObject}->Translate('printed by');
            my $Page      = $LayoutObject->{LanguageObject}->Translate('Page');
            my $Time      = $LayoutObject->{Time};
            my $Url       = ' ';
            if ( $ENV{REQUEST_URI} ) {
                $Url = $ConfigObject->Get('HttpType') . '://'
                    . $ConfigObject->Get('FQDN')
                    . $ENV{REQUEST_URI};
            }

            # get maximum number of pages
            my $MaxPages = $ConfigObject->Get('PDF::MaxPages');
            if ( !$MaxPages || $MaxPages < 1 || $MaxPages > 1000 ) {
                $MaxPages = 100;
            }

            # create the header
            my $CellData;
            my $CounterRow  = 0;
            my $CounterHead = 0;
            for my $Content ( @{$HeadArrayRef} ) {
                $CellData->[$CounterRow]->[$CounterHead]->{Content} = $Content;
                $CellData->[$CounterRow]->[$CounterHead]->{Font}    = 'ProportionalBold';
                $CounterHead++;
            }
            if ( $CounterHead > 0 ) {
                $CounterRow++;
            }

            # create the content array
            for my $Row (@StatArray) {
                my $CounterColumn = 0;
                for my $Content ( @{$Row} ) {
                    $CellData->[$CounterRow]->[$CounterColumn]->{Content} = $Content;
                    $CounterColumn++;
                }
                $CounterRow++;
            }

            # output 'No matches found', if no content was given
            if ( !$CellData->[0]->[0] ) {
                $CellData->[0]->[0]->{Content} = $LayoutObject->{LanguageObject}->Translate('No matches found.');
            }

            # page params
            my %User = $Kernel::OM->Get('Kernel::System::User')->GetUserData( UserID => $Self->{UserID} );
            my %PageParam;
            $PageParam{PageOrientation} = 'landscape';
            $PageParam{MarginTop}       = 30;
            $PageParam{MarginRight}     = 40;
            $PageParam{MarginBottom}    = 40;
            $PageParam{MarginLeft}      = 40;
            $PageParam{HeaderRight}     = $ConfigObject->Get('Stats::StatsHook') . $Stat->{StatNumber};
            $PageParam{FooterLeft}      = $Url;
            $PageParam{HeadlineLeft}    = $Title;
            $PageParam{HeadlineRight}   = $PrintedBy . ' '
                . $User{UserFirstname} . ' '
                . $User{UserLastname} . ' ('
                . $User{UserEmail} . ') '
                . $Time;

            # table params
            my %TableParam;
            $TableParam{CellData}            = $CellData;
            $TableParam{Type}                = 'Cut';
            $TableParam{FontSize}            = 6;
            $TableParam{Border}              = 0;
            $TableParam{BackgroundColorEven} = '#AAAAAA';
            $TableParam{BackgroundColorOdd}  = '#DDDDDD';
            $TableParam{Padding}             = 1;
            $TableParam{PaddingTop}          = 3;
            $TableParam{PaddingBottom}       = 3;

            # create new pdf document
            $PDFObject->DocumentNew(
                Title  => $ConfigObject->Get('Product') . ': ' . $Title,
                Encode => $LayoutObject->{UserCharset},
            );

            # start table output
            $PDFObject->PageNew(
                %PageParam,
                FooterRight => $Page . ' 1',
            );
            COUNT:
            for ( 2 .. $MaxPages ) {

                # output table (or a fragment of it)
                %TableParam = $PDFObject->Table( %TableParam, );

                # stop output or output next page
                last COUNT if $TableParam{State};

                $PDFObject->PageNew(
                    %PageParam,
                    FooterRight => $Page . ' ' . $_,
                );
            }

            # return the pdf document
            my $PDFString = $PDFObject->DocumentOutput();
            return $LayoutObject->Attachment(
                Filename    => $Filename . '.pdf',
                ContentType => 'application/pdf',
                Content     => $PDFString,
                Type        => 'inline',
            );
        }

        # HTML Output
        else {
            # $Stat->{Table} = $Self->_OutputHTMLTable(
            #     Head => $HeadArrayRef,
            #     Data => \@StatArray,
            # );

            $Stat->{Title} = $Title;

            # presentation
            my $Output = $LayoutObject->PrintHeader( Value => $Title );
            $Output .= $LayoutObject->Output(
                Data => {
                    %{$Stat},
                    HeaderRow => $HeadArrayRef,
                    DataRows  => \@StatArray,
                },
                TemplateFile => 'AgentStatistics/RenderStatisticsResultData/Print',
            );
            $Output .= $LayoutObject->PrintFooter();
            return $Output;
        }
    }

    # graph
    elsif ( $Param{Format} =~ m{^GD::Graph\.*}x ) {

        # make graph
        my $Ext   = 'png';
        my $Graph = $Self->{StatsObject}->GenerateGraph(
            Array        => \@StatArray,
            HeadArrayRef => $HeadArrayRef,
            Title        => $Title,
            Format       => $Param{Format},
            GraphSize    => $Param{GraphSize},
        );

        # error messages if there is no graph
        if ( !$Graph ) {
            if ( $Param{Format} =~ m{^GD::Graph::pie}x ) {
                return $LayoutObject->ErrorScreen(
                    Message => 'You use invalid data! Perhaps there are no results.',
                );
            }
            return $LayoutObject->ErrorScreen(
                Message => "Too much data, can't use it with graph!",
            );
        }

        # return image to browser
        return $LayoutObject->Attachment(
            Filename    => $Filename . '.' . $Ext,
            ContentType => "image/$Ext",
            Content     => $Graph,
            Type        => 'attachment',             # not inline because of bug# 2757
        );
    }
}

sub _Notify {
    my ( $Self, %Param ) = @_;

    my $NotifyOutput = '';

    # get layout object
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # check if need params are available
    for (qw(StatData Section)) {
        if ( !$Param{$_} ) {
            return $LayoutObject->ErrorScreen( Message => "_Notify: Need $_!" );
        }
    }

    # CompletenessCheck
    my @Notify = $Self->{StatsObject}->CompletenessCheck(
        StatData => $Param{StatData},
        Section  => $Param{Section},
    );
    for my $Ref (@Notify) {
        $NotifyOutput .= $LayoutObject->Notify( %{$Ref} );
    }
    return $NotifyOutput;
}

sub _Timeoutput {
    my ( $Self, %Param ) = @_;

    my %Timeoutput;

    # get layout object
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # check if need params are available
    if ( !$Param{TimePeriodFormat} ) {
        return $LayoutObject->ErrorScreen(
            Message => '_Timeoutput: Need TimePeriodFormat!'
        );
    }

    # get time object
    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

    # get time
    my ( $Sec, $Min, $Hour, $Day, $Month, $Year ) = $TimeObject->SystemTime2Date(
        SystemTime => $TimeObject->SystemTime(),
    );
    my $Element = $Param{Element};
    my %TimeConfig;

    # default time configuration
    $TimeConfig{Format}                     = $Param{TimePeriodFormat};
    $TimeConfig{ $Element . 'StartYear' }   = $Year - 1;
    $TimeConfig{ $Element . 'StartMonth' }  = 1;
    $TimeConfig{ $Element . 'StartDay' }    = 1;
    $TimeConfig{ $Element . 'StartHour' }   = 0;
    $TimeConfig{ $Element . 'StartMinute' } = 0;
    $TimeConfig{ $Element . 'StartSecond' } = 1;
    $TimeConfig{ $Element . 'StopYear' }    = $Year;
    $TimeConfig{ $Element . 'StopMonth' }   = 12;
    $TimeConfig{ $Element . 'StopDay' }     = 31;
    $TimeConfig{ $Element . 'StopHour' }    = 23;
    $TimeConfig{ $Element . 'StopMinute' }  = 59;
    $TimeConfig{ $Element . 'StopSecond' }  = 59;
    for (qw(Start Stop)) {
        $TimeConfig{Prefix} = $Element . $_;

        # time setting if available
        if (
            $Param{ 'Time' . $_ }
            && $Param{ 'Time' . $_ } =~ m{^(\d\d\d\d)-(\d\d)-(\d\d)\s(\d\d):(\d\d):(\d\d)$}xi
            )
        {
            $TimeConfig{ $Element . $_ . 'Year' }   = $1;
            $TimeConfig{ $Element . $_ . 'Month' }  = $2;
            $TimeConfig{ $Element . $_ . 'Day' }    = $3;
            $TimeConfig{ $Element . $_ . 'Hour' }   = $4;
            $TimeConfig{ $Element . $_ . 'Minute' } = $5;
            $TimeConfig{ $Element . $_ . 'Second' } = $6;
        }
        $Timeoutput{ 'Time' . $_ } = $LayoutObject->BuildDateSelection(%TimeConfig);
    }

    # Solution I (TimeExtended)
    my %TimeLists;
    for ( 1 .. 60 ) {
        $TimeLists{TimeRelativeCount}{$_} = sprintf( "%02d", $_ );
        $TimeLists{TimeScaleCount}{$_}    = sprintf( "%02d", $_ );
    }
    for (qw(TimeRelativeCount TimeScaleCount)) {
        $Timeoutput{$_} = $LayoutObject->BuildSelection(
            Data       => $TimeLists{$_},
            Name       => $Element . $_,
            SelectedID => $Param{$_},
        );
    }

    if ( $Param{TimeRelativeCount} && $Param{TimeRelativeUnit} ) {
        $Timeoutput{CheckedRelative} = 'checked="checked"';
    }
    else {
        $Timeoutput{CheckedAbsolut} = 'checked="checked"';
    }

    my %TimeScale = _TimeScaleBuildSelection();

    $Timeoutput{TimeScaleUnit} = $LayoutObject->BuildSelection(
        %TimeScale,
        Name       => $Element,
        SelectedID => $Param{SelectedValues}[0],
    );

    $Timeoutput{TimeRelativeUnit} = $LayoutObject->BuildSelection(
        %TimeScale,
        Name       => $Element . 'TimeRelativeUnit',
        SelectedID => $Param{TimeRelativeUnit},
        OnChange   => "Core.Agent.Stats.SelectRadiobutton('Relativ', '$Element" . "TimeSelect')",
    );

    # to show only the selected Attributes in the view mask
    my $Multiple = 1;
    my $Size     = 5;

    if ( $Param{OnlySelectedAttributes} ) {

        $TimeScale{Data} = $Param{SelectedValues};

        $Multiple = 0;
        $Size     = 1;
    }

    $Timeoutput{TimeSelectField} = $LayoutObject->BuildSelection(
        %TimeScale,
        Name       => $Element,
        SelectedID => $Param{SelectedValues},
        Multiple   => $Multiple,
        Size       => $Size,
    );

    return %Timeoutput;
}

sub _TimeScaleBuildSelection {

    my %TimeScaleBuildSelection = (
        Data => {
            Second => 'second(s)',
            Minute => 'minute(s)',
            Hour   => 'hour(s)',
            Day    => 'day(s)',
            Week   => 'week(s)',
            Month  => 'month(s)',
            Year   => 'year(s)',
        },
        Sort           => 'IndividualKey',
        SortIndividual => [ 'Second', 'Minute', 'Hour', 'Day', 'Week', 'Month', 'Year' ]
    );

    return %TimeScaleBuildSelection;
}

sub _TimeScale {
    my %TimeScale = (
        'Second' => {
            Position => 1,
            Value    => 'second(s)',
        },
        'Minute' => {
            Position => 2,
            Value    => 'minute(s)',
        },
        'Hour' => {
            Position => 3,
            Value    => 'hour(s)',
        },
        'Day' => {
            Position => 4,
            Value    => 'day(s)',
        },
        'Week' => {
            Position => 5,
            Value    => 'week(s)',
        },
        'Month' => {
            Position => 6,
            Value    => 'month(s)',
        },
        'Year' => {
            Position => 7,
            Value    => 'year(s)',
        },
    );

    return \%TimeScale;
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

sub _StopWordsServerErrorsGet {
    my ( $Self, %Param ) = @_;

    # get needed objects
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    if ( !%Param ) {
        $LayoutObject->FatalError( Message => "Got no values to check." );
    }

    my %StopWordsServerErrors;
    if ( !$TicketObject->SearchStringStopWordsUsageWarningActive() ) {
        return %StopWordsServerErrors;
    }

    my %SearchStrings;

    FIELD:
    for my $Field ( sort keys %Param ) {
        next FIELD if !defined $Param{$Field};
        next FIELD if !length $Param{$Field};

        $SearchStrings{$Field} = $Param{$Field};
    }

    if (%SearchStrings) {

        my $StopWords = $TicketObject->SearchStringStopWordsFind(
            SearchStrings => \%SearchStrings
        );

        FIELD:
        for my $Field ( sort keys %{$StopWords} ) {
            next FIELD if !defined $StopWords->{$Field};
            next FIELD if ref $StopWords->{$Field} ne 'ARRAY';
            next FIELD if !@{ $StopWords->{$Field} };

            $StopWordsServerErrors{ $Field . 'Invalid' }        = 'ServerError';
            $StopWordsServerErrors{ $Field . 'InvalidTooltip' } = $LayoutObject->{LanguageObject}->Translate(
                'Please remove the following words because they cannot be used for the ticket restrictions:'
                )
                . ' '
                . join( ',', sort @{ $StopWords->{$Field} } );
        }
    }

    return %StopWordsServerErrors;
}

sub _StopWordFieldsGet {
    my ( $Self, %Param ) = @_;

    my %StopWordFields = (
        'From'    => 1,
        'To'      => 1,
        'Cc'      => 1,
        'Subject' => 1,
        'Body'    => 1,
    );

    return %StopWordFields;
}

1;
