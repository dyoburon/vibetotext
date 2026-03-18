using System.Windows.Controls;
using VibeToText.ViewModels;

namespace VibeToText.UI.Views;

public partial class SettingsView : UserControl
{
    public SettingsView()
    {
        InitializeComponent();
    }

    private void ModelComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (DataContext is MainViewModel vm && ModelComboBox.SelectedItem is string model)
        {
            if (vm.ChangeWhisperModelCommand.CanExecute(model))
                vm.ChangeWhisperModelCommand.Execute(model);
        }
    }
}
