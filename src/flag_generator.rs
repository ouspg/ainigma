
use hmac::{digest::InvalidLength, Hmac, Mac};
use rand::{rngs::StdRng, Rng, SeedableRng};
use sha3::Sha3_256;
use uuid::Uuid;

type Hmac256 = Hmac<Sha3_256>;

pub fn generate_flag32() -> Result<String, rand::Error> {
    let mut rng = StdRng::from_entropy();
    let hex: [u8; 32] = rng.gen();
    let s = hex.iter().map(|b| format!("{:02x}", b)).collect();
    Ok(s)
}

pub fn generate_hmac(uuid: Uuid, secret: String, taskid: String) -> Result<String, InvalidLength> {
    let input = format!("{}-{}", secret, uuid.as_hyphenated());
    let slice = input.as_bytes();
    let mut mac = Hmac256::new_from_slice(slice)?;
    mac.update(taskid.as_bytes());

    let result = mac.finalize();
    let bytes = result.into_bytes();
    let s = format!("{:x}", bytes);
    return Ok(s);
}

pub fn compare_hmac(hmac: String, uuid: Uuid, secret: String, taskid: String) -> Result<bool, InvalidLength> {
    let input = format!("{}-{}", secret, uuid.as_hyphenated());
    let slice = input.as_bytes();
    let mut mac = Hmac256::new_from_slice(slice)?;
    mac.update(taskid.as_bytes());

    let result = mac.finalize();
    let bytes = result.into_bytes();
    let s = format!("{:x}", bytes);
    return Ok(s == hmac);
}

pub fn generate_userseed(uuid: Uuid) -> Result<String, rand::Error>{
    let (_, uuidvalue) = uuid.as_u64_pair();
    let mut rng = StdRng::seed_from_u64(uuidvalue);
    let hex: [u8; 32] = rng.gen();
    let s = hex.iter().map(|b| format!("{:02x}", b)).collect();
    Ok(s)
}

pub fn generate_uuid() -> Result<Uuid, uuid::Error> {
    let id = Uuid::now_v7();
    return Ok(id);
}
