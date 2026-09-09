# EncounterDetails-IronmonExtension

Track encounter details and an ordered action timeline for each battle throughout a run.

The HP bars use the same 48-pixel scale as https://github.com/WaffleSmacker/IronmonHpRuler-IronmonExtension, with markers at 10% and 25% intervals. An optional label such as `17/48 pixels` reports only the saved rendered bar fill; it is not the Pokemon's HP, and exact HP is never written to the battle log.

Battle snapshots also show ongoing weather and each active Pokemon's non-neutral stat stages, such as `+2 ATK` or `-1 SPE`.

<img alt="Piggy button on tracker being used to show previous encounters for a mon" src="https://github.com/jwunderl/EncounterDetails-IronmonExtension/assets/5615930/73af98de-7d4d-4bb3-bf1c-d2cfb80d00fc" width="50%" height="50%"/>

See https://github.com/besteon/Ironmon-Tracker/wiki/Tracker-Add-ons for details on tracker add ons.

This can be added to your tracker by copying [EncounterDetails.lua](./EncounterDetails.lua) into the trackers `/extensions` folder, and then enabling it in the game through the settings menu.

In the extension screen, there are four options:

- remove the pig from the opposing pokemon in the battle screen (the text below it saying when it was last encountered can still be used to enter the screen)
- ignore wild encounters and track only trainer encounters.
- disable battle-log storage and keep only encounter history.
- show or hide the `N/48 pixels` label beside timeline HP bars.

To view a battle timeline, open a Pokemon's encounter history, select an encounter, and click **Battle log**. Use the left and right arrows to step through the initial state and each action in order.

If you are outside of battle, you can still look up pokemon details from the extension details screen:

![Alternate entry path from extensions screen, and switching mons within extension screen](https://github.com/jwunderl/EncounterDetails-IronmonExtension/assets/5615930/a30cf77e-4d12-45ad-855f-c62807dce6b5)
