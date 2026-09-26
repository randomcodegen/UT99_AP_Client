class APMenuItem extends UMenuModMenuItem;

function Execute()
{
    MenuItem.Owner.Root.CreateWindow(class'APMenuWindow', 70, 15, 500, 450);
}

defaultproperties
{
    MenuCaption="&Archipelago"
    MenuHelp="Connect to a multiworld and play unlocked bot matches."
}
