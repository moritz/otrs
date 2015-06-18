// --
// Copyright (C) 2001-2011 OTRS AG, http://otrs.org/
// --
// This software comes with ABSOLUTELY NO WARRANTY. For details, see
// the enclosed file COPYING for license information (AGPL). If you
// did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
// --

"use strict";

var Core = Core || {};
Core.Agent = Core.Agent || {};

/**
 * @namespace Core.Agent.Statistics
 * @memberof Core.Agent
 * @author OTRS AG
 * @description
 *      This namespace contains the special module functions for the Statistics module.
 */
Core.Agent.Statistics = (function (TargetNS) {

    /**
     * @name InitAddScreen
     * @memberof Core.Agent.Statistics
     * @function
     * @description
     *      Initialize the add screen. Contains basically some logic to react on which
     *      of the big select buttons the agent uses. Afterwards, the specification widget
     *      is being loaded according to the clicked button.
     */
    TargetNS.InitAddScreen = function () {

        $('.BigButtons li a').bind('click', function () {
            var $Link = $(this);

            $('.BigButtons li a').removeClass('Active');
            $(this).addClass('Active');

            $('#GeneralSpecifications').fadeIn(function() {

                $('#GeneralSpecifications .Content').addClass('Center').html('<span class="AJAXLoader"></span>');
                $('#SaveWidget').hide();

                var URL = Core.Config.Get('Baselink'),
                Data = {
                    Action: 'AgentStatistics',
                    Subaction: 'GeneralSpecificationsWidgetAJAX',
                    StatisticPreselection: $Link.data('statistic-preselection')
                };
                Core.AJAX.FunctionCall(URL, Data, function(Response) {
                    $('#GeneralSpecifications .Content').removeClass('Center').html(Response);
                    $('#SaveWidget').show();
                }, 'html');
            });

            return false;
        });
    };

    TargetNS.XAxisElementAdd = function(ElementName) {
        var $Element = $('#XAxisWidgetContainer .XAxisElement' + ElementName);
        $Element.clone().appendTo($('#XAxisFormFields'));
    };

    /**
     * @name InitEditScreen
     * @memberof Core.Agent.Statistics
     * @function
     * @description
     *      Initialize the edit screen.
     */
    TargetNS.InitEditScreen = function () {
        $('button.EditXAxis').on('click', function() {

            function RebuildEditXAxisDialogAddSelection() {
                $('#EditXAxisDialog .Add select').empty();
                $.each($('#XAxisWidgetContainer .XAxisElement'), function() {
                    var $XAxisElement = $(this),
                        $Option = $($.parseHTML('<option></option>')),
                        ElementName = $XAxisElement.data('element');

                    if ($('#EditXAxisDialog .Fields .XAxisElement' + ElementName).length) {
                        return;
                    }

                    $Option.val(ElementName)
                        .text($XAxisElement.find('> label').text())
                        .appendTo('#EditXAxisDialog .Add select');
                });
            }

            function EditXAxisDialogAdd(ElementName) {
                var $Element = $('#XAxisWidgetContainer .XAxisElement' + ElementName);
                $Element.clone().appendTo($('#EditXAxisDialog .Fields'));
                $('#EditXAxisDialog .Add').hide();
            }

            function EditXAxisDialogDelete(ElementName) {
                $('#EditXAxisDialog .Fields .XAxisElement' + ElementName).remove();
                $('#EditXAxisDialog .Add').show();
                RebuildEditXAxisDialogAddSelection();
            }

            function EditXAxisDialogSave() {
                $('#XAxisFormFields').empty();
                $('#EditXAxisDialog .Fields').children().appendTo('#XAxisFormFields');
                // Cloning does not clone the selected state, only the "selected" HTML attribute.
                // Therefore we need to make sure that the attribute matches the current state
                //  so that we can clone the fields later again for use in the dialog.
                $('#XAxisFormFields option:not(:selected)').removeAttr('selected');
                $('#XAxisFormFields option:selected').attr('selected', 'selected');
                $('#XAxisFormFields input:not(:checked)').removeAttr('checked');
                $('#XAxisFormFields input:checked').attr('checked', 'checked');
                Core.UI.Dialog.CloseDialog($('.Dialog'));
            }

            function EditXAxisDialogCancel() {
                Core.UI.Dialog.CloseDialog($('.Dialog'));
            }

            Core.UI.Dialog.ShowContentDialog(
                '<div id="EditXAxisDialog" style="max-height: 500px; width: 600px; overflow: auto;"></div>',
                '123',
                100,
                'Center',
                true,
                [
                    { Label: "Save", Class: 'Primary', Type: 'Close', Function: EditXAxisDialogSave },
                    { Label: "Cancel", Class: '', Type: 'Close', Function: EditXAxisDialogCancel }
                ],
                false
            );
            $('#EditXAxisDialogTemplate').children().clone().appendTo('#EditXAxisDialog');

            if ($('#XAxisFormFields').children().length) {
                $('#EditXAxisDialog .Add').hide();
                $('#XAxisFormFields').children().clone().appendTo('#EditXAxisDialog .Fields');
            }
            else {
                $('#EditXAxisDialog .Add').show();
            }
            RebuildEditXAxisDialogAddSelection();

            $('#EditXAxisDialog .Add .AddButton').on('click', function(){
                EditXAxisDialogAdd($('#EditXAxisDialog .Add select').val());
                return false;
            });

            $('#EditXAxisDialog .Fields').on('click', '.DeleteButton', function(){
                EditXAxisDialogDelete($(this).parents('.XAxisElement').data('element'));
                return false;
            });

            return false;
        });
    };

    return TargetNS;
}(Core.Agent.Statistics || {}));
