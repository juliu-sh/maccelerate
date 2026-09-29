import AppKit
import Foundation

// Export the approved glass artwork as a macOS app icon. The source PNG also
// contains a broad gray outer shadow; the white tile is the intended silhouette.
guard CommandLine.arguments.count == 3 ||
      (CommandLine.arguments.count == 4 && CommandLine.arguments[3] == "--icon-composer-layer") else {
  fatalError("Usage: swift dist/prepare-icon.swift source.png output.png [--icon-composer-layer]")
}
let iconComposerLayer=CommandLine.arguments.count == 4
let sourceURL=URL(fileURLWithPath:CommandLine.arguments[1])
let outputURL=URL(fileURLWithPath:CommandLine.arguments[2])
let source=NSBitmapImageRep(data:try Data(contentsOf:sourceURL))!
let width=source.pixelsWide, height=source.pixelsHigh
guard width == height, width >= 1024, source.samplesPerPixel == 4 else {
  fatalError("Icon source must be a square RGBA PNG of at least 1024 pixels")
}
let bytes=source.bitmapData!
// Find the white tile by its bright, opaque pixels. The surrounding gray
// shadow is deliberately excluded from the app icon's visible silhouette.
var left=[Int](repeating:width,count:height)
var right=[Int](repeating:-1,count:height)
for y in 0..<height {
  for x in 0..<width {
    let p=y*source.bytesPerRow+x*4
    if bytes[p]>220 && bytes[p+1]>220 && bytes[p+2]>220 && bytes[p+3]>240 {
      left[y]=min(left[y],x);right[y]=max(right[y],x)
    }
  }
}
let first=left.firstIndex(where:{$0<width})!,last=left.lastIndex(where:{$0<width})!
// The source's first and last bright row have a one-pixel threshold artifact.
// Continue the neighboring curve through those rows before antialiasing it.
let bodyWidth=right[height/2]-left[height/2]+1
let endInset=Int((Double(bodyWidth)*0.01).rounded())
left[first]=left[first+1]+endInset
right[first]=right[first+1]-endInset
left[last]=left[last-1]+endInset
right[last]=right[last-1]-endInset
var silhouette=[Float](repeating:0,count:width*height)
for y in first...last {
  if right[y]>=left[y] {
    for x in left[y]...right[y] {silhouette[y*width+x]=1}
  }
}
var horizontal=[Float](repeating:0,count:width*height)
for y in 0..<height {
  for x in 0..<width {
    let i=y*width+x
    let l=x>0 ? silhouette[i-1] : 0
    let r=x+1<width ? silhouette[i+1] : 0
    horizontal[i]=(l+2*silhouette[i]+r)/4
  }
}
var coverage=[Float](repeating:0,count:width*height)
for y in 0..<height {
  for x in 0..<width {
    let i=y*width+x
    let t=y>0 ? horizontal[i-width] : 0
    let b=y+1<height ? horizontal[i+width] : 0
    coverage[i]=(t+2*horizontal[i]+b)/4
  }
}
let masked=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
let out=masked.bitmapData!
func smoothstep(_ a:Double,_ b:Double,_ x:Double)->Double {let t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)}
let bodyHeight=last-first+1
for y in 0..<height {
  for x in 0..<width {
    let i=y*width+x,p=y*source.bytesPerRow+x*4,q=y*masked.bytesPerRow+x*4
    // Preserve the artwork's continuous corner curve. A second circular clip
    // cuts too deeply into it and makes the corners look unlike macOS icons.
    let c=Double(coverage[i])
    if c<=0 {out[q]=0;out[q+1]=0;out[q+2]=0;out[q+3]=0;continue}
    let dist=max(0,min(x-left[y],right[y]-x,y-first,last-y))
    let whiten=1-smoothstep(0,18,Double(dist))
    let nearWhite=[252.0,253.0,254.0]
    for channel in 0..<3 {
      let value=(1-whiten)*Double(bytes[p+channel])+whiten*nearWhite[channel]
      out[q+channel]=UInt8(clamping:Int(value.rounded()))
    }
    out[q+3]=UInt8(clamping:Int((255*c).rounded()))
  }
}
let outputSize=1024
// Icon Composer receives a full square without a pre-rounded outer edge and
// lets macOS apply its own mask. Keep the legacy ICNS layout for older builds.
let scale=(iconComposerLayer ? 1.0 : 0.803)*Double(outputSize)/Double(bodyWidth)
let fullWidth=Double(width)*scale
// The source tile is slightly wider than it is tall. Keep its visible body square.
let verticalScale=scale*Double(bodyWidth)/Double(bodyHeight)
let fullHeight=Double(height)*verticalScale
let bodyYOffset=(Double(height)-Double(first+last+1))/2*verticalScale
let raster=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:outputSize,pixelsHigh:outputSize,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
let context=NSGraphicsContext(bitmapImageRep:raster)!
let image=NSImage(size:NSSize(width:width,height:height));image.addRepresentation(masked)
NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
context.imageInterpolation = .high
let background=iconComposerLayer
  ? NSColor(calibratedRed:252.0/255,green:253.0/255,blue:254.0/255,alpha:1)
  : NSColor.clear
background.setFill();NSRect(x:0,y:0,width:outputSize,height:outputSize).fill()
image.draw(in:NSRect(x:(Double(outputSize)-fullWidth)/2+0.5,y:(Double(outputSize)-fullHeight)/2-bodyYOffset,width:fullWidth,height:fullHeight),from:.zero,operation:.sourceOver,fraction:1)
context.flushGraphics();NSGraphicsContext.restoreGraphicsState()
try raster.representation(using:.png,properties:[:])!.write(to:outputURL)
print("body",bodyWidth,"source px; scale",scale,"output target",Int(Double(bodyWidth)*scale),"px")
