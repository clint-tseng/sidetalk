
import Foundation
import Cocoa
import ReactiveCocoa

struct LayoutState {
    let order: [ Contact : Int ];
    let activated: Bool;
}

// TODO: split into V/VM?
class MainView: NSView {
    internal let connection: Connection;

    private let _statusTile: StatusTile;
    private var _contactTiles = QuickCache<Contact, ContactTile>();

    // drawing ks. should these go elsewhere?
    let allPadding = CGFloat(150);
    let listPadding = CGFloat(35);
    let tileSize = NSSize(width: 300, height: 50);
    let tilePadding = CGFloat(4);

    init(frame: CGRect, connection: Connection) {
        self.connection = connection;
        self._statusTile = StatusTile(connection: connection, frame: NSRect(origin: NSPoint.zero, size: frame.size));

        super.init(frame: frame);

        self.addSubview(self._statusTile);
        self._statusTile.frame.origin = NSPoint(
            x: frame.width - self.tileSize.width - self.tilePadding + (self.tileSize.height * 0.55),
            y: frame.height - self.allPadding
        );

        self.prepare();
    }

    private func prepare() {
        // draw new contacts as required.
        let tiles = self.connection.contacts.map({ (contacts) -> [ContactTile] in
            contacts.map { contact in self._contactTiles.get(contact, orElse: { self.drawOne(contact); }); };
        });

        // calculate the correct sort of all contacts.
        let sort = self.connection.contacts.map({ contacts -> [ Contact : Int ] in
            let availableContacts = contacts.filter({ contact in contact.onlineOnce && contact.presenceOnce == nil });
            let awayContacts = contacts.filter { contact in contact.onlineOnce && contact.presenceOnce != nil };

            let sorted = availableContacts + awayContacts;
            var result = Dictionary<Contact, Int>();
            for (idx, contact) in sorted.enumerate() {
                result[contact] = idx;
            }
            return result;
        });

        // relayout as required.
        sort.combineLatestWith(tiles).map { order, _ in order } // (Order)
            .combineWithDefault(GlobalInteraction.sharedInstance.activated, defaultValue: false) // ((Order, ContactTile?), Bool)
            .map({ order, activated in LayoutState(order: order, activated: activated); })
            .combinePrevious(LayoutState(order: [:], activated: false))
            .observeNext { last, this in self.layout(last, this) }

        // if we are active, show all contact labels.
        tiles.combineLatestWith(GlobalInteraction.sharedInstance.activated)
            .combineLatestWith(sort).map{ ($0.0, $0.1, $1) } // ghetto flatten
            .observeNext { (tiles, activated, sort) in tiles.forEach { tile in tile.showLabel = activated && sort[tile.contact] != nil; } };

        // if we are active, claim window focus. vice versa.
        GlobalInteraction.sharedInstance.activated.observeNext { activated in
            if activated { NSApplication.sharedApplication().activateIgnoringOtherApps(true); }
            else         { GlobalInteraction.sharedInstance.lastApp?.activateWithOptions(NSApplicationActivationOptions.ActivateIgnoringOtherApps); }
        }
    }

    private func drawOne(contact: Contact) -> ContactTile {
        let newTile = ContactTile(
            frame: self.frame,
            size: tileSize,
            contact: contact
        );
        dispatch_async(dispatch_get_main_queue(), { self.addSubview(newTile); });
        return newTile;
    }

    private func layout(lastState: LayoutState, _ thisState: LayoutState) {
        NSLog("relayout");
        dispatch_async(dispatch_get_main_queue(), {
            // deal with self
            if lastState.activated != thisState.activated {
                let tile = self._statusTile;
                let anim = CABasicAnimation.init(keyPath: "position");

                let off = NSPoint.zero;
                let on =  NSPoint(x: self.tileSize.height * -0.55, y: 0);

                if (thisState.activated) {
                    anim.fromValue = NSValue.init(point: off);
                    anim.toValue = NSValue.init(point: on);
                } else {
                    anim.fromValue = NSValue.init(point: on);
                    anim.toValue = NSValue.init(point: off);
                }

                anim.duration = thisState.activated ? 0.03 : 0.15;
                tile.layer!.removeAnimationForKey("contacttile-layout");
                tile.layer!.addAnimation(anim, forKey: "contacttile-layout");
                tile.layer!.position = thisState.activated ? on : off;
            }

            // deal with actual contacts
            for tile in self._contactTiles.all() {
                let anim = CABasicAnimation.init(keyPath: "position");

                let last = lastState.order[tile.contact];
                let this = thisState.order[tile.contact];

                // make sure we're offscreen if we're not to be shown
                if last == nil && this == nil {
                    tile.layer!.position = NSPoint(x: 0, y: -900);
                    continue;
                }

                // calculate positions. TODO: mutable. gross.
                var from: NSPoint;
                var to: NSPoint;

                let xOn = self.frame.width - self.tileSize.width - self.tilePadding;
                let xHalf = self.frame.width - self.tileSize.width + (self.tileSize.height * 0.55);
                let xOff = self.frame.width - self.tileSize.width + self.tileSize.height;

                let yLast = self.frame.height - self.allPadding - self.listPadding - ((self.tileSize.height + self.tilePadding) * CGFloat((last ?? 0) + 1));
                let yThis = self.frame.height - self.allPadding - self.listPadding - ((self.tileSize.height + self.tilePadding) * CGFloat((this ?? 0) + 1));

                if last == nil { from = NSPoint(x: xOff, y: yThis); }
                else if lastState.activated { from = NSPoint(x: xOn, y: yLast); }
                else { from = NSPoint(x: xHalf, y: yLast); }

                if this == nil { to = NSPoint(x: xOff, y: yLast); }
                else if thisState.activated { to = NSPoint(x: xOn, y: yThis); }
                else { to = NSPoint(x: xHalf, y: yThis); }

                anim.fromValue = NSValue.init(point: from);
                anim.toValue = NSValue.init(point: to);
                anim.duration = NSTimeInterval((!lastState.activated && thisState.activated ? 0.05 : 0.2) + (0.02 * Double(this ?? 0)));
                tile.layer!.removeAnimationForKey("contacttile-layout");
                tile.layer!.addAnimation(anim, forKey: "contacttile-layout");
                tile.layer!.position = to;
            }
        });
    }

    required init(coder: NSCoder) {
        fatalError("no coder");
    }
}
