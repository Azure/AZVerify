param seed string

var suffix = uniqueString(seed)

output accountName string = 'st${suffix}'
output generatedGuid string = guid(suffix)
