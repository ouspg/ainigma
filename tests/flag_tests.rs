#[cfg(test)]
mod tests {
    use super::*;
    use autograder::flag_generator;
    use uuid::Uuid
    #[test]
    fn test_new() {
        assert!(generate_uuid().is_ok());
    }
    #[test]
    fn test_compare_hmac() {
        let id = Uuid::now_v7();
        let secret = "Work".to_string();
        let taskid = "task1".to_string();
        let secret2 = "Work".to_string();
        let taskid2 = "task1".to_string();
        let hash = generate_hmac(id, secret, taskid).expect("error");
        print!("{}", hash);
        assert!(compare_hmac(hash, id, secret2, taskid2).expect("should work"))
    }

    #[test]
    fn test_rand() {
        assert!(generate_flag32().is_ok());
    }
}
