class APCatalogProbe extends DeathMatchPlus;

function PostBeginPlay()
{
    Super.PostBeginPlay();
    SetTimer(0.5, false);
}

function Timer()
{
    local Inventory Item;
    local FortStandard Fort;
    foreach AllActors(class'Inventory', Item)
        if (Item.Owner == None && !Item.bDeleteMe && !Item.bHeldItem && !Item.bTossedOut)
            Log("AP PICKUP|" $ Item.Name $ "|" $ Item.Class $ "|" $ Item.Location
                $ "|" $ Item.CollisionRadius $ "|" $ Item.CollisionHeight);
    foreach AllActors(class'FortStandard', Fort)
        Log("AP FORT|" $ Fort.Name $ "|" $ Fort.Tag $ "|" $ Fort.bFinalFort);
    Log("AP CATALOG DONE");
    ConsoleCommand("exit");
}

defaultproperties
{
    bLocalLog=False
    bWorldLog=False
}
