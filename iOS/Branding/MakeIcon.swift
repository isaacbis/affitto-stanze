import CoreGraphics
import ImageIO
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let size = 1024
let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
let c = CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:size*4,space:rgb,bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
func color(_ r:CGFloat,_ g:CGFloat,_ b:CGFloat,_ a:CGFloat=1)->CGColor {CGColor(colorSpace:rgb,components:[r,g,b,a])!}
let gradient=CGGradient(colorsSpace:rgb,colors:[color(0.25,0.18,0.75),color(0.17,0.41,0.88),color(0.04,0.61,0.65)] as CFArray,locations:[0,0.55,1])!
c.drawLinearGradient(gradient,start:CGPoint(x:80,y:1000),end:CGPoint(x:940,y:20),options:[.drawsBeforeStartLocation,.drawsAfterEndLocation])
c.setFillColor(color(1,1,1,0.07));c.fillEllipse(in:CGRect(x:600,y:640,width:600,height:600))
c.setFillColor(color(0.04,0.83,0.73,0.15));c.fillEllipse(in:CGRect(x:-170,y:-160,width:650,height:650))
// Architectural doorway, drawn as vector geometry.
c.saveGState();c.setShadow(offset:CGSize(width:0,height:-12),blur:25,color:color(0.03,0.06,0.25,0.24))
let frame=CGPath(roundedRect:CGRect(x:254,y:222,width:390,height:590),cornerWidth:44,cornerHeight:44,transform:nil)
c.addPath(frame);c.setStrokeColor(color(1,1,1));c.setLineWidth(40);c.strokePath();c.restoreGState()
let leaf=CGMutablePath();leaf.move(to:CGPoint(x:280,y:247));leaf.addLine(to:CGPoint(x:466,y:304));leaf.addLine(to:CGPoint(x:466,y:737));leaf.addLine(to:CGPoint(x:280,y:785));leaf.closeSubpath()
c.addPath(leaf);c.setFillColor(color(1,1,1,0.93));c.fillPath()
c.setFillColor(color(0.23,0.33,0.76));c.fillEllipse(in:CGRect(x:416,y:504,width:20,height:30))
// Reservation confirmation badge.
c.saveGState();c.setShadow(offset:CGSize(width:0,height:-8),blur:22,color:color(0.03,0.06,0.25,0.25))
c.setFillColor(color(1,1,1));c.fillEllipse(in:CGRect(x:536,y:156,width:288,height:288));c.restoreGState()
c.setFillColor(color(0.12,0.66,0.34));c.fillEllipse(in:CGRect(x:553,y:173,width:254,height:254))
c.setStrokeColor(color(1,1,1));c.setLineWidth(24);c.setLineCap(.round);c.setLineJoin(.round)
c.move(to:CGPoint(x:611,y:299));c.addLine(to:CGPoint(x:658,y:252));c.addLine(to:CGPoint(x:747,y:347));c.strokePath()
let image=c.makeImage()!
let dest=CGImageDestinationCreateWithURL(output as CFURL,"public.png" as CFString,1,nil)!
CGImageDestinationAddImage(dest,image,nil)
precondition(CGImageDestinationFinalize(dest))
