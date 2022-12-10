import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            MetalView().frame(minWidth: 600, maxWidth: 600, minHeight: 600, maxHeight: 600)
            HStack {
                Button(
                    "Toggle X rotation",
                    action: settings.toggleXRotation
                )
            
                Button(
                    "Toggle Y rotation",
                    action: settings.toggleYRotation
                )
            
                Button(
                    "Toggle Z rotation",
                    action: settings.toggleZRotation
                )
            }.padding()
        }
        
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

